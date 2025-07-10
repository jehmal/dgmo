# Evolution --generate Flag Implementation

## Summary

Successfully implemented the `--generate` flag for the evolve command in the DGMO CLI. This flag
enables code generation based on performance data analysis.

## Changes Made

### 1. Added --generate Flag Option

- Location: `/opencode/packages/opencode/src/cli/cmd/evolve.ts`
- Added option definition with alias 'g'
- Description: "generate code improvements based on performance data"
- Type: boolean, default: false

### 2. Updated DGMBridge Import

- Changed from local dgm/bridge to @opencode/dgm-integration
- Fixed method compatibility (shutdown → close)
- Ensures access to the execute() method

### 3. Implemented Generate Logic

Added conditional logic in the handler to check for --generate flag:

- Calls `generateImprovements()` instead of `analyzeAndEvolve()`
- Displays generated improvements with `displayGeneratedImprovements()`
- Applies improvements with `applyGeneratedImprovements()`

### 4. New Functions Added

#### generateImprovements()

- Prepares performance patterns for DGM
- Calls DGM's "generate_code_improvements" method
- Returns GenerationResults with generated code

#### displayGeneratedImprovements()

- Shows generated code improvements
- Displays expected performance gains
- Lists specific improvements for each tool

#### applyGeneratedImprovements()

- Applies generated code via DGM
- Calls "apply_generated_code" method
- Tracks success/failure counts
- Saves generation history

#### saveGenerationHistory()

- Persists generation results to evolution/generation/ directory
- Tracks patterns and generated code over time

### 5. New Interfaces

#### GenerationResults

```typescript
interface GenerationResults {
  generatedCode: Array<{
    toolName: string;
    originalCode: string;
    improvedCode: string;
    improvements: string[];
    performanceGain: number;
  }>;
  patterns: {
    errorPatterns: any[];
    performancePatterns: any[];
    successPatterns: any[];
  };
}
```

## Usage

```bash
# Generate code improvements based on performance data
opencode evolve --generate

# Generate with verbose output
opencode evolve --generate --verbose

# Generate and auto-apply improvements
opencode evolve --generate --auto-apply

# Generate for specific session
opencode evolve --generate --session <session-id>
```

## Testing

Created test script: `test-evolve-generate.sh`

- Tests flag recognition in help
- Tests generate with analyze mode
- Tests generate with verbose output

## Integration Points

The implementation integrates with:

1. DGM Bridge for Python-based code generation
2. Session performance data collection
3. Storage system for history tracking
4. UI system for progress display

## Next Steps

1. Ensure DGM Python side has the required methods:
   - `generate_code_improvements`
   - `apply_generated_code`
2. Test with real performance data
3. Monitor generation quality and performance gains
4. Consider adding more options like:
   - `--target-performance` for specific gain targets
   - `--safe-mode` for conservative improvements
   - `--language` for specific language targeting
