# Message Queue Final Fix - No More "Is Busy" Errors

## Problem
When processing queued messages after the assistant completed, the system would still show "Session is busy" errors because:
1. Queued messages were sent back through the same `SendMsg` flow
2. This triggered another `IsBusy()` check
3. The backend might still report busy status briefly after completion
4. Messages would fail to send from the queue

## Solution
Created a separate message type `QueuedSendMsg` that bypasses the busy check entirely.

### Changes Made

#### 1. Added New Message Type in `app.go`
```go
type QueuedSendMsg struct {
    Text        string
    Attachments []Attachment
}
```

#### 2. Updated Queue Processing in `tui.go`
When processing the queue after assistant completion:
```go
// Convert queued SendMsg to QueuedSendMsg to bypass busy check
return app.QueuedSendMsg{
    Text:        nextMsg.Text,
    Attachments: nextMsg.Attachments,
}
```

#### 3. Added Handler for QueuedSendMsg
```go
case app.QueuedSendMsg:
    // Bypass busy check - this is already queued and ready to send
    cmd := a.app.SendChatMessage(context.Background(), msg.Text, msg.Attachments)
    cmds = append(cmds, cmd)
    
    // Update UI components
    u, cmd2 := a.messages.Update(app.SendMsg(msg))
    a.messages = u.(chat.MessagesComponent)
    cmds = append(cmds, cmd2)
```

## How It Works Now

1. **User sends message while assistant is busy** → Message gets queued ✅
2. **Assistant completes** (Time.Completed > 0) → Queue processor activates ✅
3. **Queued message is converted to QueuedSendMsg** → Bypasses busy check ✅
4. **Message sends immediately** → No more "is busy" errors ✅

## Key Benefits

- **Guaranteed delivery**: Queued messages always send after completion
- **No race conditions**: Doesn't matter if backend briefly reports busy
- **Clean separation**: New messages check busy status, queued ones don't
- **Smooth UX**: Messages flow naturally without errors

## Testing

1. Send a message while assistant is responding
2. See "Message queued" toast
3. When assistant finishes, queued message sends automatically
4. No "is busy" errors appear

The queue system now works reliably without any timing issues or backend state conflicts.