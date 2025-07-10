#!/usr/bin/env bun

// Test script to check provider state initialization
import { spawn } from "child_process"
import { promisify } from "util"

const exec = promisify(require("child_process").exec)

async function testProviderState() {
  console.log("Testing provider state through DGMO CLI...")
  
  try {
    // First check if dgmo auth shows anthropic
    console.log("\n1. Checking authentication status:")
    const { stdout: authStatus } = await exec("dgmo auth status")
    console.log(authStatus)
    
    // List available models
    console.log("\n2. Listing available models:")
    const { stdout: models } = await exec("dgmo models")
    console.log(models)
    
    // Check if anthropic models are available
    if (models.includes("anthropic/")) {
      console.log("✅ Anthropic models are available in the main session")
    } else {
      console.log("❌ Anthropic models not found in the main session")
    }
    
    // Now let's test a simple task to see if sub-agents work
    console.log("\n3. Testing sub-agent task execution:")
    console.log("Creating test file to trigger sub-agent...")
    
    // Create a test file with a simple task request
    const testPrompt = `Use the Task tool to create a sub-agent that says "Hello from sub-agent". The task description should be "Test sub-agent" and the prompt should be "Say hello from sub-agent"`
    
    await exec(`echo '${testPrompt}' > test-sub-agent-prompt.txt`)
    
    console.log("\nTo test sub-agents:")
    console.log("1. Run: dgmo")
    console.log("2. Type the following command:")
    console.log("   Use the Task tool to create a sub-agent that says 'Hello from sub-agent'")
    console.log("3. Watch for ProviderModelNotFoundError")
    
  } catch (error) {
    console.error("Test failed:", error.message)
  }
}

// Run the test
testProviderState()