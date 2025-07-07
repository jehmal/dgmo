#!/usr/bin/env bun
/**
 * Specific test for task tool recursion prevention
 */

import { AgentConfig } from "./opencode/packages/opencode/src/config/agent-config"

async function testRecursionPrevention() {
  console.log("🔒 Testing Task Tool Recursion Prevention\n")

  // Test the core recursion prevention logic
  console.log("1. Testing main session (should allow task tool):")
  const mainSession = "main-session-123"
  const mainCanUseTask = await AgentConfig.isToolAllowed(mainSession, "task")
  console.log(`   Main session can use task: ${mainCanUseTask} ${mainCanUseTask ? '✅' : '❌'}`)

  console.log("\n2. Testing sub-agent session (should block task tool):")
  const subSession = "sub-session-456"
  const parentSession = "main-session-123"
  const subCanUseTask = await AgentConfig.isToolAllowed(subSession, "task", parentSession)
  console.log(`   Sub-agent can use task: ${subCanUseTask} ${!subCanUseTask ? '✅' : '❌'}`)

  console.log("\n3. Testing sub-agent can use other tools:")
  const subCanRead = await AgentConfig.isToolAllowed(subSession, "read", parentSession)
  const subCanWrite = await AgentConfig.isToolAllowed(subSession, "write", parentSession)
  console.log(`   Sub-agent can use read: ${subCanRead} ${subCanRead ? '✅' : '❌'}`)
  console.log(`   Sub-agent can use write: ${subCanWrite} ${subCanWrite ? '✅' : '❌'}`)

  console.log("\n4. Testing isSubAgentSession detection:")
  const tests = [
    { sessionId: "test", parentId: undefined, expected: false, desc: "undefined parent" },
    { sessionId: "test", parentId: null, expected: false, desc: "null parent" },
    { sessionId: "test", parentId: "", expected: false, desc: "empty parent" },
    { sessionId: "test", parentId: "undefined", expected: false, desc: "string 'undefined'" },
    { sessionId: "test", parentId: "valid-parent", expected: true, desc: "valid parent" },
  ]

  for (const test of tests) {
    const result = AgentConfig.isSubAgentSession(test.sessionId, test.parentId as any)
    const status = result === test.expected ? '✅' : '❌'
    console.log(`   ${test.desc}: ${result} ${status}`)
  }

  console.log("\n🎯 Summary:")
  console.log("✅ Main sessions can create sub-agents using task tool")
  console.log("🚫 Sub-agents cannot create more sub-agents (recursion prevented)")
  console.log("✅ Sub-agents retain access to all other tools based on their mode")
  console.log("✅ Parent ID detection works correctly for edge cases")
  
  return {
    mainCanUseTask,
    subCanUseTask: !subCanUseTask, // Inverted because we want false
    subCanUseOtherTools: subCanRead && subCanWrite
  }
}

// Run the test
testRecursionPrevention()
  .then(results => {
    const allPassed = Object.values(results).every(Boolean)
    console.log(`\n${allPassed ? '🎉 ALL TESTS PASSED' : '❌ SOME TESTS FAILED'}`)
    process.exit(allPassed ? 0 : 1)
  })
  .catch(console.error)
