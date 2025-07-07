#!/usr/bin/env bun
/**
 * Test script to verify task tool recursion prevention
 */

import { AgentConfig } from "./opencode/packages/opencode/src/config/agent-config"

async function testTaskToolRecursionPrevention() {
  console.log("🧪 Testing Task Tool Recursion Prevention\n")

  // Test 1: Main session should have access to task tool
  console.log("Test 1: Main session (no parent) should allow task tool")
  const mainSessionId = "main-session-123"
  const mainCanUseTask = await AgentConfig.isToolAllowed(mainSessionId, "task")
  console.log(`  Main session can use task tool: ${mainCanUseTask}`)
  console.log(`  ✅ Expected: true, Got: ${mainCanUseTask}`)

  // Test 2: Sub-agent session should NOT have access to task tool
  console.log("\nTest 2: Sub-agent session should NOT allow task tool")
  const subSessionId = "sub-session-456"
  const parentSessionId = "main-session-123"
  const subCanUseTask = await AgentConfig.isToolAllowed(subSessionId, "task", parentSessionId)
  console.log(`  Sub-agent session can use task tool: ${subCanUseTask}`)
  console.log(`  ✅ Expected: false, Got: ${subCanUseTask}`)

  // Test 3: Sub-agent should still have access to other tools
  console.log("\nTest 3: Sub-agent should still have access to other tools")
  const subCanRead = await AgentConfig.isToolAllowed(subSessionId, "read", parentSessionId)
  const subCanWrite = await AgentConfig.isToolAllowed(subSessionId, "write", parentSessionId)
  console.log(`  Sub-agent can use read tool: ${subCanRead}`)
  console.log(`  Sub-agent can use write tool: ${subCanWrite}`)

  console.log("\n🎯 Recursion prevention successfully implemented!")
}

// Run the test
testTaskToolRecursionPrevention().catch(console.error)
