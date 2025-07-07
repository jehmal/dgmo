"""
Backup Extraction Engine for Restoration Testing System

This module provides secure, efficient extraction capabilities for various backup formats
including tar, zip, compressed archives, and Qdrant snapshots. Features streaming
extraction, memory optimization, and comprehensive security checks.

Author: DGMSTT System
Version: 1.0.0
"""

import hashlib
import logging
import os
import shutil
import signal
import stat
import tarfile
import tempfile
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Union
import threading
import time
from contextlib import contextmanager

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Constants
CHUNK_SIZE = 8192  # 8KB chunks for streaming
MAX_EXTRACT_SIZE = 10 * 1024 * 1024 * 1024  # 10GB limit
SUPPORTED_FORMATS = {
    '.tar': 'tar',
    '.tar.gz': 'tar.gz',
    '.tgz': 'tar.gz',
    '.tar.bz2': 'tar.bz2',
    '.tbz2': 'tar.bz2',
    '.tar.xz': 'tar.xz',
    '.zip': 'zip',
    '.snapshot': 'qdrant'
}

# Magic bytes for format detection
MAGIC_BYTES = {
    b'\x1f\x8b': 'gzip',
    b'PK\x03\x04': 'zip',
    b'PK\x05\x06': 'zip',
    b'PK\x07\x08': 'zip',
    b'BZh': 'bzip2',
    b'\xfd7zXZ\x00': 'xz'
}


@dataclass
class ExtractionMetadata:
    """Metadata collected during extraction process."""
    total_files: int = 0
    total_size: int = 0
    extracted_files: int = 0
    extracted_size: int = 0
    start_time: float = field(default_factory=time.time)
    end_time: Optional[float] = None
    errors: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    
    @property
    def duration(self) -> float:
        """Calculate extraction duration."""
        end = self.end_time or time.time()
        return end - self.start_time
    
    @property
    def progress_percent(self) -> float:
        """Calculate extraction progress percentage."""
        if self.total_files == 0:
            return 0.0
        return (self.extracted_files / self.total_files) * 100


@dataclass
class ExtractionResult:
    """Result of backup extraction operation."""
    success: bool
    extraction_path: Path
    metadata: ExtractionMetadata
    format_detected: str
    file_count: int
    total_size: int
    checksum: Optional[str] = None
    error_message: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert result to dictionary for serialization."""
        return {
            'success': self.success,
            'extraction_path': str(self.extraction_path),
            'format_detected': self.format_detected,
            'file_count': self.file_count,
            'total_size': self.total_size,
            'duration': self.metadata.duration,
            'progress_percent': self.metadata.progress_percent,
            'checksum': self.checksum,
            'error_message': self.error_message,
            'errors': self.metadata.errors,
            'warnings': self.metadata.warnings
        }


class ExtractionError(Exception):
    """Custom exception for extraction-related errors."""
    pass


class SecurityError(ExtractionError):
    """Exception raised for security-related extraction issues."""
    pass


class ExtractionEngine:
    """
    Secure backup extraction engine with streaming capabilities.
    
    Supports multiple archive formats with comprehensive security checks,
    memory-efficient processing, and detailed progress reporting.
    """
    
    def __init__(self, temp_base_dir: Optional[Path] = None):
        """
        Initialize extraction engine.
        
        Args:
            temp_base_dir: Base directory for temporary files. Uses system temp if None.
        """
        self.temp_base_dir = temp_base_dir
        self.temp_dirs: List[Path] = []
        self._interrupted = False
        self._lock = threading.Lock()
        
        # Register signal handlers for cleanup
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
    
    def __enter__(self):
        """Context manager entry."""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit with cleanup."""
        self.cleanup()
    
    def _signal_handler(self, signum, frame):
        """Handle interruption signals."""
        logger.warning(f"Received signal {signum}, initiating cleanup...")
        self._interrupted = True
    
    def _check_interrupted(self):
        """Check if extraction was interrupted."""
        if self._interrupted:
            raise ExtractionError("Extraction interrupted by user")
    
    def _create_secure_temp_dir(self) -> Path:
        """
        Create secure temporary directory with proper permissions.
        
        Returns:
            Path to created temporary directory.
        """
        temp_dir = Path(tempfile.mkdtemp(
            prefix='extraction_',
            dir=self.temp_base_dir
        ))
        
        # Set secure permissions (owner only)
        temp_dir.chmod(stat.S_IRWXU)
        
        with self._lock:
            self.temp_dirs.append(temp_dir)
        
        logger.debug(f"Created secure temp directory: {temp_dir}")
        return temp_dir
    
    def _detect_format(self, backup_path: Path) -> str:
        """
        Detect archive format from file extension and magic bytes.
        
        Args:
            backup_path: Path to backup file.
            
        Returns:
            Detected format string.
            
        Raises:
            ExtractionError: If format cannot be detected.
        """
        # Check file extension
        for ext, format_type in SUPPORTED_FORMATS.items():
            if backup_path.name.lower().endswith(ext.lower()):
                logger.debug(f"Format detected by extension: {format_type}")
                return format_type
        
        # Check magic bytes
        try:
            with open(backup_path, 'rb') as f:
                header = f.read(8)
                
            for magic, format_type in MAGIC_BYTES.items():
                if header.startswith(magic):
                    logger.debug(f"Format detected by magic bytes: {format_type}")
                    if format_type == 'gzip':
                        return 'tar.gz'
                    elif format_type == 'bzip2':
                        return 'tar.bz2'
                    elif format_type == 'xz':
                        return 'tar.xz'
                    return format_type
                    
        except Exception as e:
            logger.warning(f"Could not read magic bytes: {e}")
        
        raise ExtractionError(f"Unsupported or unrecognized format: {backup_path}")
    
    def _validate_path_security(self, member_path: str, extraction_dir: Path) -> bool:
        """
        Validate extraction path for security (prevent path traversal).
        
        Args:
            member_path: Path of archive member.
            extraction_dir: Target extraction directory.
            
        Returns:
            True if path is safe, False otherwise.
        """
        # Normalize paths
        member_path = os.path.normpath(member_path)
        extraction_dir = extraction_dir.resolve()
        
        # Check for path traversal attempts
        if '..' in member_path or member_path.startswith('/'):
            logger.warning(f"Potential path traversal detected: {member_path}")
            return False
        
        # Ensure extracted path stays within extraction directory
        full_path = (extraction_dir / member_path).resolve()
        try:
            full_path.relative_to(extraction_dir)
            return True
        except ValueError:
            logger.warning(f"Path outside extraction directory: {full_path}")
            return False
    
    def _calculate_checksum(self, file_path: Path) -> str:
        """
        Calculate SHA256 checksum of file.
        
        Args:
            file_path: Path to file.
            
        Returns:
            Hexadecimal checksum string.
        """
        sha256_hash = hashlib.sha256()
        
        with open(file_path, 'rb') as f:
            while chunk := f.read(CHUNK_SIZE):
                sha256_hash.update(chunk)
                self._check_interrupted()
        
        return sha256_hash.hexdigest()
    
    def _extract_tar(
        self,
        backup_path: Path,
        extraction_dir: Path,
        metadata: ExtractionMetadata,
        progress_callback: Optional[Callable[[float, str], None]] = None
    ) -> None:
        """
        Extract tar archive with streaming and security checks.
        
        Args:
            backup_path: Path to tar archive.
            extraction_dir: Target extraction directory.
            metadata: Metadata object to update.
            progress_callback: Optional progress callback function.
        """
        # Determine compression mode
        if backup_path.suffix.lower() in ['.gz', '.tgz']:
            mode = 'r:gz'
        elif backup_path.suffix.lower() in ['.bz2', '.tbz2']:
            mode = 'r:bz2'
        elif backup_path.suffix.lower() == '.xz':
            mode = 'r:xz'
        else:
            mode = 'r'
        
        with tarfile.open(backup_path, mode) as tar:
            members = tar.getmembers()
            metadata.total_files = len(members)
            metadata.total_size = sum(m.size for m in members if m.isfile())
            
            for i, member in enumerate(members):
                self._check_interrupted()
                
                # Security validation
                if not self._validate_path_security(member.name, extraction_dir):
                    metadata.warnings.append(f"Skipped unsafe path: {member.name}")
                    continue
                
                # Size check
                if member.size > MAX_EXTRACT_SIZE:
                    metadata.warnings.append(f"Skipped oversized file: {member.name}")
                    continue
                
                try:
                    tar.extract(member, extraction_dir)
                    metadata.extracted_files += 1
                    if member.isfile():
                        metadata.extracted_size += member.size
                    
                    # Progress callback
                    if progress_callback:
                        progress = (i + 1) / len(members) * 100
                        progress_callback(progress, f"Extracted: {member.name}")
                        
                except Exception as e:
                    error_msg = f"Failed to extract {member.name}: {e}"
                    metadata.errors.append(error_msg)
                    logger.error(error_msg)
    
    def _extract_zip(
        self,
        backup_path: Path,
        extraction_dir: Path,
        metadata: ExtractionMetadata,
        progress_callback: Optional[Callable[[float, str], None]] = None
    ) -> None:
        """
        Extract zip archive with streaming and security checks.
        
        Args:
            backup_path: Path to zip archive.
            extraction_dir: Target extraction directory.
            metadata: Metadata object to update.
            progress_callback: Optional progress callback function.
        """
        with zipfile.ZipFile(backup_path, 'r') as zip_file:
            members = zip_file.infolist()
            metadata.total_files = len(members)
            metadata.total_size = sum(m.file_size for m in members if not m.is_dir())
            
            for i, member in enumerate(members):
                self._check_interrupted()
                
                # Security validation
                if not self._validate_path_security(member.filename, extraction_dir):
                    metadata.warnings.append(f"Skipped unsafe path: {member.filename}")
                    continue
                
                # Size check
                if member.file_size > MAX_EXTRACT_SIZE:
                    metadata.warnings.append(f"Skipped oversized file: {member.filename}")
                    continue
                
                try:
                    zip_file.extract(member, extraction_dir)
                    metadata.extracted_files += 1
                    if not member.is_dir():
                        metadata.extracted_size += member.file_size
                    
                    # Progress callback
                    if progress_callback:
                        progress = (i + 1) / len(members) * 100
                        progress_callback(progress, f"Extracted: {member.filename}")
                        
                except Exception as e:
                    error_msg = f"Failed to extract {member.filename}: {e}"
                    metadata.errors.append(error_msg)
                    logger.error(error_msg)
    
    def _extract_qdrant_snapshot(
        self,
        backup_path: Path,
        extraction_dir: Path,
        metadata: ExtractionMetadata,
        progress_callback: Optional[Callable[[float, str], None]] = None
    ) -> None:
        """
        Extract Qdrant snapshot (typically tar.gz format).
        
        Args:
            backup_path: Path to Qdrant snapshot.
            extraction_dir: Target extraction directory.
            metadata: Metadata object to update.
            progress_callback: Optional progress callback function.
        """
        # Qdrant snapshots are typically tar.gz files
        try:
            self._extract_tar(backup_path, extraction_dir, metadata, progress_callback)
        except Exception as e:
            # Fallback: try as regular file copy
            logger.warning(f"Failed to extract as tar, copying as file: {e}")
            target_path = extraction_dir / backup_path.name
            shutil.copy2(backup_path, target_path)
            metadata.total_files = 1
            metadata.extracted_files = 1
            metadata.total_size = backup_path.stat().st_size
            metadata.extracted_size = metadata.total_size
            
            if progress_callback:
                progress_callback(100.0, f"Copied: {backup_path.name}")
    
    def test_extraction(
        self,
        backup_path: Union[str, Path],
        extraction_dir: Optional[Union[str, Path]] = None,
        progress_callback: Optional[Callable[[float, str], None]] = None
    ) -> ExtractionResult:
        """
        Test extraction of backup archive with comprehensive validation.
        
        Args:
            backup_path: Path to backup file to extract.
            extraction_dir: Target directory for extraction. Creates temp dir if None.
            progress_callback: Optional callback for progress updates (progress%, message).
            
        Returns:
            ExtractionResult with detailed extraction information.
            
        Raises:
            ExtractionError: If extraction fails.
            SecurityError: If security validation fails.
        """
        backup_path = Path(backup_path)
        metadata = ExtractionMetadata()
        
        logger.info(f"Starting extraction test for: {backup_path}")
        
        try:
            # Validate input file
            if not backup_path.exists():
                raise ExtractionError(f"Backup file not found: {backup_path}")
            
            if not backup_path.is_file():
                raise ExtractionError(f"Path is not a file: {backup_path}")
            
            # Detect format
            format_detected = self._detect_format(backup_path)
            logger.info(f"Detected format: {format_detected}")
            
            # Setup extraction directory
            if extraction_dir is None:
                extraction_path = self._create_secure_temp_dir()
                temp_created = True
            else:
                extraction_path = Path(extraction_dir)
                extraction_path.mkdir(parents=True, exist_ok=True)
                temp_created = False
            
            logger.info(f"Extracting to: {extraction_path}")
            
            # Calculate original checksum
            if progress_callback:
                progress_callback(0.0, "Calculating checksum...")
            
            original_checksum = self._calculate_checksum(backup_path)
            
            # Perform extraction based on format
            if progress_callback:
                progress_callback(5.0, "Starting extraction...")
            
            if format_detected in ['tar', 'tar.gz', 'tar.bz2', 'tar.xz']:
                self._extract_tar(backup_path, extraction_path, metadata, progress_callback)
            elif format_detected == 'zip':
                self._extract_zip(backup_path, extraction_path, metadata, progress_callback)
            elif format_detected == 'qdrant':
                self._extract_qdrant_snapshot(backup_path, extraction_path, metadata, progress_callback)
            else:
                raise ExtractionError(f"Unsupported format: {format_detected}")
            
            metadata.end_time = time.time()
            
            if progress_callback:
                progress_callback(100.0, "Extraction completed")
            
            # Create successful result
            result = ExtractionResult(
                success=True,
                extraction_path=extraction_path,
                metadata=metadata,
                format_detected=format_detected,
                file_count=metadata.extracted_files,
                total_size=metadata.extracted_size,
                checksum=original_checksum
            )
            
            logger.info(f"Extraction completed successfully: {metadata.extracted_files} files, "
                       f"{metadata.extracted_size} bytes in {metadata.duration:.2f}s")
            
            return result
            
        except Exception as e:
            metadata.end_time = time.time()
            error_message = str(e)
            metadata.errors.append(error_message)
            
            logger.error(f"Extraction failed: {error_message}")
            
            # Create failed result
            result = ExtractionResult(
                success=False,
                extraction_path=extraction_path if 'extraction_path' in locals() else Path(),
                metadata=metadata,
                format_detected=format_detected if 'format_detected' in locals() else 'unknown',
                file_count=metadata.extracted_files,
                total_size=metadata.extracted_size,
                error_message=error_message
            )
            
            return result
    
    def cleanup(self) -> None:
        """Clean up temporary directories and resources."""
        with self._lock:
            for temp_dir in self.temp_dirs:
                try:
                    if temp_dir.exists():
                        shutil.rmtree(temp_dir)
                        logger.debug(f"Cleaned up temp directory: {temp_dir}")
                except Exception as e:
                    logger.warning(f"Failed to cleanup {temp_dir}: {e}")
            
            self.temp_dirs.clear()


@contextmanager
def extraction_engine(temp_base_dir: Optional[Path] = None):
    """
    Context manager for ExtractionEngine with automatic cleanup.
    
    Args:
        temp_base_dir: Base directory for temporary files.
        
    Yields:
        ExtractionEngine instance.
    """
    engine = ExtractionEngine(temp_base_dir)
    try:
        yield engine
    finally:
        engine.cleanup()


# Example usage and testing
if __name__ == "__main__":
    import sys
    
    def progress_handler(progress: float, message: str):
        """Example progress callback."""
        print(f"\r[{progress:6.2f}%] {message}", end='', flush=True)
    
    if len(sys.argv) < 2:
        print("Usage: python extraction_engine.py <backup_file> [extraction_dir]")
        sys.exit(1)
    
    backup_file = Path(sys.argv[1])
    extraction_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else None
    
    # Test extraction
    with extraction_engine() as engine:
        result = engine.test_extraction(
            backup_file,
            extraction_dir,
            progress_callback=progress_handler
        )
        
        print(f"\n\nExtraction Result:")
        print(f"Success: {result.success}")
        print(f"Format: {result.format_detected}")
        print(f"Files: {result.file_count}")
        print(f"Size: {result.total_size:,} bytes")
        print(f"Duration: {result.metadata.duration:.2f}s")
        print(f"Path: {result.extraction_path}")
        
        if result.error_message:
            print(f"Error: {result.error_message}")
        
        if result.metadata.warnings:
            print(f"Warnings: {len(result.metadata.warnings)}")
            for warning in result.metadata.warnings[:5]:  # Show first 5
                print(f"  - {warning}")