#!/usr/bin/env bun
/**
 * Check if task tool is properly loaded and available
 */

import { Provider } from "./opencode/packages/opencode/src/provider/provider"
import { App } from "./opencode/packages/opencode/src/app/app"

console.log("=== TASK TOOL AVAILABILITY CHECK ===\n")

await App.provide({ cwd: "/mnt/c/Users/jehma/Desktop/AI/DGMSTT/opencode" }, async () => {
  // Check all available tools
  console.log("1. Checking Provider Tools:")
  
  const providers = ["anthropic", "openai", "google"]
  
  for (const providerId of providers) {
    try {
      const tools = await Provider.tools(providerId)
      console.log(`\n${providerId} tools (${tools.length} total):`)
      
      // Look for task tool
      const taskTool = tools.find(t => t.id === "task")
      if (taskTool) {
        console.log("  ✓ TASK TOOL FOUND!")
        console.log("    ID:", taskTool.id)
        console.log("    Description:", taskTool.description.substring(0, 100) + "...")
      } else {
        console.log("  ✗ Task tool NOT in list")
        console.log("  Available tools:", tools.map(t => t.id).join(", "))
      }
    } catch (e) {
      console.log(`  Error loading ${providerId} tools:`, e.message)
    }
  }
  
  // Check the TOOLS array directly
  console.log("\n2. Checking TOOLS Array:")
  const toolsModule = await import("./opencode/packages/opencode/src/provider/provider")
  console.log("  Note: Task tool should be loaded dynamically via getTaskTool()")
  
  // Test the dynamic loader
  console.log("\n3. Testing Dynamic Task Tool Loader:")
  try {
    // This mimics what Provider.tools() should do
    const taskModule = await import("./opencode/packages/opencode/src/tool/task")
    if (taskModule.TaskTool) {
      console.log("  ✓ TaskTool module loaded successfuly!")
      console.log("  ID:", taskModule.TaskTool.id)
      console.log("  Parameters:", Object.keys(taskModule.TaskTool.parameters.shape))
    } else {
      console.log("  ✗ TaskTool not exported from module")
    }
  } catch (e) {
    console.log("  ✗ Error loading task module:", e)
  }
})
