# DGMO Evolution System - Complete User Guide

## What is Evolution?

DGMO can analyze how you use it and automatically improve itself based on your patterns.

## Step-by-Step Workflow

### Step 1: Analyze Your Usage

```bash
dgmo evolve --analyze
```

- Shows your usage statistics
- Identifies patterns and errors
- No changes made yet - just analysis

### Step 2: Generate Improvements

```bash
dgmo evolve --generate
```

- Creates improvement suggestions based on analysis
- Still no changes - just proposals
- Shows what improvements it wants to make

### Step 3: Test Improvements (Automatic)

```bash
dgmo evolve --test
```

- Tests proposed changes in isolated sandbox
- Verifies improvements actually work
- Measures performance gains
- No changes to your actual system yet

### Step 4: Review & Approve

```bash
dgmo evolve --review
```

- Shows you exactly what will change
- Displays test results
- You can approve or reject each change
- Nothing happens without your approval

### Step 5: Apply Approved Changes

```bash
dgmo evolve --apply
```

- Only applies changes you approved
- Creates backup before making changes
- Can be rolled back if needed

## Safety Features

### Built-in Safeguards

- **Sandbox Testing**: All changes tested in isolation first
- **User Approval Required**: Nothing changes without your OK
- **Automatic Backups**: Before any changes are applied
- **Rollback Capability**: Can undo changes if problems occur
- **Performance Validation**: Only applies improvements that actually work
- **No Breaking Changes**: System checks compatibility

### Risk Levels

- **Low Risk**: Performance optimizations, bug fixes
- **Medium Risk**: New features, workflow changes
- **High Risk**: Core system modifications (requires extra confirmation)

## Common Scenarios

### Scenario 1: Fix Detected Errors

If analysis shows errors (like the "ruff not found"):

1. Evolution will propose installing missing tools
2. Or suggest alternative tools that work
3. You approve the fix
4. Error goes away automatically

### Scenario 2: Speed Improvements

If analysis shows slow operations:

1. Evolution identifies bottlenecks
2. Proposes optimizations
3. Tests show 50% speed improvement
4. You approve, system gets faster

### Scenario 3: Workflow Optimization

If you always use certain tools together:

1. Evolution notices the pattern
2. Suggests combining them
3. Creates new streamlined command
4. Your workflow becomes more efficient

## Quick Start Commands

### See Everything at Once

```bash
# Full automatic evolution (with prompts)
dgmo evolve

# Analyze only (safe, read-only)
dgmo evolve --analyze

# Dry run (shows what would change)
dgmo evolve --dry-run

# Auto-approve low-risk changes
dgmo evolve --auto-approve-low-risk
```

## Understanding the Output

### Analysis Output

```
Analysis Period: 2 days (84 sessions)    # How much data analyzed
Total Operations: 1,362                  # How many things you did
Success Rate: 91.5%                      # What percentage worked

Tool Usage:
✓ tool_name  X calls, Y% success, Zms avg   # Which tools you use most
! error_name X calls, 0% success             # Problems found
```

### What the Symbols Mean

- ✓ = Working well
- ! = Problem detected
- ⚠ = Warning/suggestion
- 🔄 = Update available
- 🚀 = Performance improvement possible

## FAQ

### Is it safe?

Yes. Multiple safety layers:

1. Tests in sandbox first
2. Requires your approval
3. Creates backups
4. Can rollback changes

### Will it break my work?

No. Evolution system:

- Never changes without permission
- Tests everything first
- Only applies proven improvements
- Keeps backups just in case

### How often should I run it?

- Weekly for best results
- After heavy usage periods
- When you notice repeated issues
- Whenever you want improvements

### Can I disable it?

Yes. Add to config:

```json
{
  "evolution": {
    "enabled": false
  }
}
```

## Advanced Options

### Configuration

```bash
# Set evolution preferences
dgmo evolve config set auto-approve-low-risk true
dgmo evolve config set test-iterations 10
dgmo evolve config set backup-before-apply true
```

### Manual Control

```bash
# Pause evolution
dgmo evolve pause

# Resume evolution
dgmo evolve resume

# Show evolution history
dgmo evolve history

# Rollback last evolution
dgmo evolve rollback
```

## Troubleshooting

### "Insufficient data"

- Use DGMO more (needs 10+ sessions)
- Run: `dgmo evolve --min-samples 5` to lower threshold

### "No improvements found"

- System is already optimized
- Try different workflows
- Check back later

### "Evolution failed"

- Check logs: `dgmo evolve logs`
- Rollback if needed: `dgmo evolve rollback`
- Report issue: `dgmo evolve report-issue`

## Best Practices

1. **Review First**: Always check what changes are proposed
2. **Start Small**: Approve low-risk changes first
3. **Monitor**: Watch system after applying changes
4. **Regular Runs**: Weekly evolution keeps system optimal
5. **Report Issues**: Help improve evolution system

## Summary

Evolution makes DGMO better automatically by:

- Learning from your usage
- Fixing repeated problems
- Optimizing performance
- Adding helpful features
- All while keeping you in control

Start with `dgmo evolve --analyze` to see what it can do for you!
