#!/usr/bin/env bun

// Test script to verify sub-agent model inheritance fix
import { Session } from "./opencode/packages/opencode/src/session"
import { Provider } from "./opencode/packages/opencode/src/provider/provider"

async function testSubAgentModelFix() {
  console.log("Testing sub-agent model inheritance fix...")
  
  try {
    // First, check if anthropic provider is available
    const providers = await Provider.list()
    console.log("\nAvailable providers:", Object.keys(providers))
    
    if (!providers.anthropic) {
      console.error("❌ Anthropic provider not found! The fix may not be working.")
      console.log("Provider list:", providers)
    } else {
      console.log("✅ Anthropic provider is available")
      console.log("Anthropic models:", Object.keys(providers.anthropic.info.models))
    }
    
    // Try to get a specific model
    try {
      const model = await Provider.getModel("anthropic", "claude-opus-4-20250514")
      console.log("✅ Successfully loaded claude-opus-4 model")
    } catch (error) {
      console.error("❌ Failed to load model:", error.message)
    }
    
  } catch (error) {
    console.error("Test failed:", error)
  }
}

// Run the test
testSubAgentModelFix()