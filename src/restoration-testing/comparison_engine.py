"""
Content Comparison Engine for Backup Verification

This module provides comprehensive file and directory comparison capabilities
for backup verification, including content integrity checks, metadata comparison,
and performance-optimized processing for large datasets.
"""

import hashlib
import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple, Union, Iterator
import fnmatch
import stat


class ComparisonMode(Enum):
    """Comparison modes for different verification strategies."""
    QUICK = "quick"          # Size and basic metadata only
    FULL = "full"           # Complete content and metadata verification
    METADATA_ONLY = "metadata_only"  # Only metadata comparison
    CHECKSUM_ONLY = "checksum_only"  # Only content checksums


class DifferenceType(Enum):
    """Types of differences that can be detected."""
    MISSING_SOURCE = "missing_source"
    MISSING_TARGET = "missing_target"
    SIZE_MISMATCH = "size_mismatch"
    CONTENT_MISMATCH = "content_mismatch"
    METADATA_MISMATCH = "metadata_mismatch"
    PERMISSION_MISMATCH = "permission_mismatch"
    TIMESTAMP_MISMATCH = "timestamp_mismatch"
    TYPE_MISMATCH = "type_mismatch"


@dataclass
class FileMetadata:
    """File metadata container."""
    path: Path
    size: int
    mtime: float
    mode: int
    is_file: bool
    is_dir: bool
    is_symlink: bool
    checksum: Optional[str] = None


@dataclass
class FileDifference:
    """Represents a difference between two files."""
    path: Path
    difference_type: DifferenceType
    source_metadata: Optional[FileMetadata] = None
    target_metadata: Optional[FileMetadata] = None
    details: str = ""


@dataclass
class ComparisonResult:
    """Comprehensive comparison result with detailed metrics."""
    source_path: Path
    target_path: Path
    comparison_mode: ComparisonMode
    total_files_processed: int = 0
    total_directories_processed: int = 0
    files_identical: int = 0
    files_different: int = 0
    files_missing_source: int = 0
    files_missing_target: int = 0
    differences: List[FileDifference] = field(default_factory=list)
    processing_time: float = 0.0
    total_bytes_processed: int = 0
    excluded_patterns: List[str] = field(default_factory=list)
    errors: List[str] = field(default_factory=list)
    
    @property
    def success_rate(self) -> float:
        """Calculate the success rate as percentage of identical files."""
        if self.total_files_processed == 0:
            return 100.0
        return (self.files_identical / self.total_files_processed) * 100.0
    
    @property
    def has_differences(self) -> bool:
        """Check if any differences were found."""
        return len(self.differences) > 0
    
    def get_summary(self) -> str:
        """Generate a human-readable summary of the comparison."""
        return (
            f"Comparison Summary:\n"
            f"  Source: {self.source_path}\n"
            f"  Target: {self.target_path}\n"
            f"  Mode: {self.comparison_mode.value}\n"
            f"  Files Processed: {self.total_files_processed}\n"
            f"  Directories Processed: {self.total_directories_processed}\n"
            f"  Identical Files: {self.files_identical}\n"
            f"  Different Files: {self.files_different}\n"
            f"  Missing in Source: {self.files_missing_source}\n"
            f"  Missing in Target: {self.files_missing_target}\n"
            f"  Success Rate: {self.success_rate:.2f}%\n"
            f"  Processing Time: {self.processing_time:.2f}s\n"
            f"  Bytes Processed: {self.total_bytes_processed:,}\n"
            f"  Errors: {len(self.errors)}\n"
        )


class ComparisonEngine:
    """
    High-performance content comparison engine for backup verification.
    
    Supports multiple comparison modes, parallel processing, and memory-efficient
    handling of large datasets.
    """
    
    def __init__(
        self,
        max_workers: Optional[int] = None,
        chunk_size: int = 8192,
        exclude_patterns: Optional[List[str]] = None,
        follow_symlinks: bool = False,
        case_sensitive: bool = True
    ):
        """
        Initialize the comparison engine.
        
        Args:
            max_workers: Maximum number of worker threads for parallel processing
            chunk_size: Chunk size for streaming file reads (bytes)
            exclude_patterns: List of glob patterns to exclude from comparison
            follow_symlinks: Whether to follow symbolic links
            case_sensitive: Whether path comparison is case-sensitive
        """
        self.max_workers = max_workers or min(32, (os.cpu_count() or 1) + 4)
        self.chunk_size = chunk_size
        self.exclude_patterns = exclude_patterns or []
        self.follow_symlinks = follow_symlinks
        self.case_sensitive = case_sensitive
        self.logger = logging.getLogger(__name__)
    
    def calculate_checksum(self, file_path: Path) -> str:
        """
        Calculate SHA-256 checksum for a file using streaming.
        
        Args:
            file_path: Path to the file
            
        Returns:
            Hexadecimal SHA-256 checksum
            
        Raises:
            IOError: If file cannot be read
        """
        sha256_hash = hashlib.sha256()
        
        try:
            with open(file_path, 'rb') as f:
                while chunk := f.read(self.chunk_size):
                    sha256_hash.update(chunk)
            return sha256_hash.hexdigest()
        except Exception as e:
            self.logger.error(f"Error calculating checksum for {file_path}: {e}")
            raise IOError(f"Cannot calculate checksum for {file_path}: {e}")
    
    def get_file_metadata(self, file_path: Path, include_checksum: bool = True) -> FileMetadata:
        """
        Extract comprehensive metadata for a file or directory.
        
        Args:
            file_path: Path to the file or directory
            include_checksum: Whether to calculate file checksum
            
        Returns:
            FileMetadata object with all relevant information
        """
        try:
            stat_result = file_path.stat()
            
            metadata = FileMetadata(
                path=file_path,
                size=stat_result.st_size,
                mtime=stat_result.st_mtime,
                mode=stat_result.st_mode,
                is_file=file_path.is_file(),
                is_dir=file_path.is_dir(),
                is_symlink=file_path.is_symlink()
            )
            
            if include_checksum and metadata.is_file and not metadata.is_symlink:
                metadata.checksum = self.calculate_checksum(file_path)
            
            return metadata
            
        except Exception as e:
            self.logger.error(f"Error getting metadata for {file_path}: {e}")
            raise
    
    def should_exclude(self, path: Path) -> bool:
        """
        Check if a path should be excluded based on patterns.
        
        Args:
            path: Path to check
            
        Returns:
            True if path should be excluded
        """
        path_str = str(path)
        if not self.case_sensitive:
            path_str = path_str.lower()
        
        for pattern in self.exclude_patterns:
            if not self.case_sensitive:
                pattern = pattern.lower()
            if fnmatch.fnmatch(path_str, pattern):
                return True
        return False
    
    def collect_files(self, root_path: Path) -> Dict[str, Path]:
        """
        Collect all files in a directory tree with relative paths as keys.
        
        Args:
            root_path: Root directory to scan
            
        Returns:
            Dictionary mapping relative paths to absolute paths
        """
        files = {}
        
        try:
            for item in root_path.rglob('*'):
                if self.should_exclude(item):
                    continue
                
                if not self.follow_symlinks and item.is_symlink():
                    continue
                
                try:
                    relative_path = item.relative_to(root_path)
                    key = str(relative_path)
                    if not self.case_sensitive:
                        key = key.lower()
                    files[key] = item
                except ValueError:
                    # Skip files outside the root path
                    continue
                    
        except Exception as e:
            self.logger.error(f"Error collecting files from {root_path}: {e}")
            raise
        
        return files
    
    def compare_metadata(
        self,
        source_metadata: FileMetadata,
        target_metadata: FileMetadata,
        mode: ComparisonMode
    ) -> List[FileDifference]:
        """
        Compare metadata between two files.
        
        Args:
            source_metadata: Source file metadata
            target_metadata: Target file metadata
            mode: Comparison mode
            
        Returns:
            List of differences found
        """
        differences = []
        
        # Check file type consistency
        if (source_metadata.is_file != target_metadata.is_file or
            source_metadata.is_dir != target_metadata.is_dir):
            differences.append(FileDifference(
                path=source_metadata.path,
                difference_type=DifferenceType.TYPE_MISMATCH,
                source_metadata=source_metadata,
                target_metadata=target_metadata,
                details=f"Type mismatch: source={'file' if source_metadata.is_file else 'dir'}, "
                       f"target={'file' if target_metadata.is_file else 'dir'}"
            ))
            return differences  # No point in further comparison
        
        # Size comparison
        if source_metadata.size != target_metadata.size:
            differences.append(FileDifference(
                path=source_metadata.path,
                difference_type=DifferenceType.SIZE_MISMATCH,
                source_metadata=source_metadata,
                target_metadata=target_metadata,
                details=f"Size mismatch: source={source_metadata.size}, target={target_metadata.size}"
            ))
        
        # Content comparison (checksum)
        if (mode in [ComparisonMode.FULL, ComparisonMode.CHECKSUM_ONLY] and
            source_metadata.is_file and target_metadata.is_file and
            source_metadata.checksum and target_metadata.checksum and
            source_metadata.checksum != target_metadata.checksum):
            differences.append(FileDifference(
                path=source_metadata.path,
                difference_type=DifferenceType.CONTENT_MISMATCH,
                source_metadata=source_metadata,
                target_metadata=target_metadata,
                details=f"Content mismatch: checksums differ"
            ))
        
        # Permission comparison
        if mode == ComparisonMode.FULL:
            if stat.S_IMODE(source_metadata.mode) != stat.S_IMODE(target_metadata.mode):
                differences.append(FileDifference(
                    path=source_metadata.path,
                    difference_type=DifferenceType.PERMISSION_MISMATCH,
                    source_metadata=source_metadata,
                    target_metadata=target_metadata,
                    details=f"Permission mismatch: source={oct(stat.S_IMODE(source_metadata.mode))}, "
                           f"target={oct(stat.S_IMODE(target_metadata.mode))}"
                ))
            
            # Timestamp comparison (with 1-second tolerance)
            if abs(source_metadata.mtime - target_metadata.mtime) > 1.0:
                differences.append(FileDifference(
                    path=source_metadata.path,
                    difference_type=DifferenceType.TIMESTAMP_MISMATCH,
                    source_metadata=source_metadata,
                    target_metadata=target_metadata,
                    details=f"Timestamp mismatch: source={source_metadata.mtime}, "
                           f"target={target_metadata.mtime}"
                ))
        
        return differences
    
    def compare_file_pair(
        self,
        relative_path: str,
        source_path: Path,
        target_path: Path,
        mode: ComparisonMode
    ) -> Tuple[List[FileDifference], int]:
        """
        Compare a single file pair.
        
        Args:
            relative_path: Relative path of the file
            source_path: Absolute path to source file
            target_path: Absolute path to target file
            mode: Comparison mode
            
        Returns:
            Tuple of (differences_list, bytes_processed)
        """
        differences = []
        bytes_processed = 0
        
        try:
            include_checksum = mode in [ComparisonMode.FULL, ComparisonMode.CHECKSUM_ONLY]
            
            source_metadata = self.get_file_metadata(source_path, include_checksum)
            target_metadata = self.get_file_metadata(target_path, include_checksum)
            
            bytes_processed = source_metadata.size
            
            if mode != ComparisonMode.QUICK or source_metadata.size != target_metadata.size:
                differences = self.compare_metadata(source_metadata, target_metadata, mode)
            
        except Exception as e:
            self.logger.error(f"Error comparing {relative_path}: {e}")
            differences.append(FileDifference(
                path=Path(relative_path),
                difference_type=DifferenceType.CONTENT_MISMATCH,
                details=f"Comparison error: {e}"
            ))
        
        return differences, bytes_processed
    
    def content_comparison(
        self,
        source_path: Union[str, Path],
        extracted_path: Union[str, Path],
        comparison_mode: str = 'full'
    ) -> ComparisonResult:
        """
        Perform comprehensive content comparison between source and extracted directories.
        
        Args:
            source_path: Path to the source directory
            extracted_path: Path to the extracted/target directory
            comparison_mode: Comparison mode ('quick', 'full', 'metadata_only', 'checksum_only')
            
        Returns:
            ComparisonResult with detailed comparison metrics and differences
        """
        start_time = time.time()
        
        source_path = Path(source_path)
        extracted_path = Path(extracted_path)
        mode = ComparisonMode(comparison_mode)
        
        result = ComparisonResult(
            source_path=source_path,
            target_path=extracted_path,
            comparison_mode=mode,
            excluded_patterns=self.exclude_patterns.copy()
        )
        
        try:
            # Validate input paths
            if not source_path.exists():
                raise FileNotFoundError(f"Source path does not exist: {source_path}")
            if not extracted_path.exists():
                raise FileNotFoundError(f"Target path does not exist: {extracted_path}")
            
            self.logger.info(f"Starting {mode.value} comparison: {source_path} vs {extracted_path}")
            
            # Collect all files from both directories
            self.logger.info("Collecting source files...")
            source_files = self.collect_files(source_path)
            
            self.logger.info("Collecting target files...")
            target_files = self.collect_files(extracted_path)
            
            # Find all unique paths
            all_paths = set(source_files.keys()) | set(target_files.keys())
            
            # Identify missing files
            missing_in_target = set(source_files.keys()) - set(target_files.keys())
            missing_in_source = set(target_files.keys()) - set(source_files.keys())
            common_paths = set(source_files.keys()) & set(target_files.keys())
            
            # Add missing file differences
            for path in missing_in_target:
                result.differences.append(FileDifference(
                    path=Path(path),
                    difference_type=DifferenceType.MISSING_TARGET,
                    details=f"File exists in source but not in target"
                ))
                result.files_missing_target += 1
            
            for path in missing_in_source:
                result.differences.append(FileDifference(
                    path=Path(path),
                    difference_type=DifferenceType.MISSING_SOURCE,
                    details=f"File exists in target but not in source"
                ))
                result.files_missing_source += 1
            
            # Compare common files in parallel
            if common_paths:
                self.logger.info(f"Comparing {len(common_paths)} common files...")
                
                with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
                    # Submit comparison tasks
                    future_to_path = {}
                    for relative_path in common_paths:
                        source_file = source_files[relative_path]
                        target_file = target_files[relative_path]
                        
                        future = executor.submit(
                            self.compare_file_pair,
                            relative_path,
                            source_file,
                            target_file,
                            mode
                        )
                        future_to_path[future] = relative_path
                    
                    # Collect results
                    for future in as_completed(future_to_path):
                        relative_path = future_to_path[future]
                        try:
                            differences, bytes_processed = future.result()
                            result.differences.extend(differences)
                            result.total_bytes_processed += bytes_processed
                            
                            if differences:
                                result.files_different += 1
                            else:
                                result.files_identical += 1
                                
                        except Exception as e:
                            error_msg = f"Error processing {relative_path}: {e}"
                            result.errors.append(error_msg)
                            self.logger.error(error_msg)
            
            # Update final statistics
            result.total_files_processed = len(all_paths)
            result.total_directories_processed = len([
                p for p in source_files.values() if p.is_dir()
            ]) + len([
                p for p in target_files.values() if p.is_dir()
            ])
            
            result.processing_time = time.time() - start_time
            
            self.logger.info(f"Comparison completed in {result.processing_time:.2f}s")
            self.logger.info(f"Success rate: {result.success_rate:.2f}%")
            
        except Exception as e:
            error_msg = f"Comparison failed: {e}"
            result.errors.append(error_msg)
            self.logger.error(error_msg)
            result.processing_time = time.time() - start_time
        
        return result
    
    def generate_detailed_report(self, result: ComparisonResult) -> str:
        """
        Generate a detailed comparison report.
        
        Args:
            result: ComparisonResult to generate report for
            
        Returns:
            Detailed report as string
        """
        report_lines = [
            "=" * 80,
            "BACKUP VERIFICATION COMPARISON REPORT",
            "=" * 80,
            "",
            result.get_summary(),
            ""
        ]
        
        if result.differences:
            report_lines.extend([
                "DIFFERENCES FOUND:",
                "-" * 40,
                ""
            ])
            
            # Group differences by type
            by_type = {}
            for diff in result.differences:
                diff_type = diff.difference_type
                if diff_type not in by_type:
                    by_type[diff_type] = []
                by_type[diff_type].append(diff)
            
            for diff_type, diffs in by_type.items():
                report_lines.extend([
                    f"{diff_type.value.upper().replace('_', ' ')} ({len(diffs)} files):",
                    ""
                ])
                
                for diff in diffs[:10]:  # Limit to first 10 per type
                    report_lines.append(f"  • {diff.path}")
                    if diff.details:
                        report_lines.append(f"    {diff.details}")
                    report_lines.append("")
                
                if len(diffs) > 10:
                    report_lines.append(f"  ... and {len(diffs) - 10} more files")
                    report_lines.append("")
        
        if result.errors:
            report_lines.extend([
                "ERRORS ENCOUNTERED:",
                "-" * 40,
                ""
            ])
            for error in result.errors:
                report_lines.append(f"  • {error}")
            report_lines.append("")
        
        report_lines.extend([
            "=" * 80,
            f"Report generated at {time.strftime('%Y-%m-%d %H:%M:%S')}",
            "=" * 80
        ])
        
        return "\n".join(report_lines)


def content_comparison(
    source_path: Union[str, Path],
    extracted_path: Union[str, Path],
    comparison_mode: str = 'full',
    max_workers: Optional[int] = None,
    exclude_patterns: Optional[List[str]] = None
) -> ComparisonResult:
    """
    Convenience function for content comparison.
    
    Args:
        source_path: Path to the source directory
        extracted_path: Path to the extracted/target directory
        comparison_mode: Comparison mode ('quick', 'full', 'metadata_only', 'checksum_only')
        max_workers: Maximum number of worker threads
        exclude_patterns: List of glob patterns to exclude
        
    Returns:
        ComparisonResult with detailed comparison metrics
    """
    engine = ComparisonEngine(
        max_workers=max_workers,
        exclude_patterns=exclude_patterns
    )
    return engine.content_comparison(source_path, extracted_path, comparison_mode)


if __name__ == "__main__":
    # Example usage
    import sys
    
    if len(sys.argv) < 3:
        print("Usage: python comparison_engine.py <source_path> <target_path> [mode]")
        sys.exit(1)
    
    source = sys.argv[1]
    target = sys.argv[2]
    mode = sys.argv[3] if len(sys.argv) > 3 else 'full'
    
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    # Run comparison
    engine = ComparisonEngine()
    result = engine.content_comparison(source, target, mode)
    
    # Print results
    print(engine.generate_detailed_report(result))
    
    # Exit with appropriate code
    sys.exit(0 if not result.has_differences else 1)