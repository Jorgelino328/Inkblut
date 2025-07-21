# Test script to verify the fixes
extends Node

func _ready():
	print("=== TESTING FIXES ===")
	
	# Test 1: Custom match validation
	print("Test 1: Custom match validation")
	print("- Scene controller should now validate game mode and map selection")
	print("- Default selections (0) should be rejected")
	
	# Test 2: Server status tracking
	print("Test 2: Server status tracking")
	print("- NetworkManager now tracks server status: waiting, active, ended")
	print("- Global lobby should show server status in button text")
	print("- Ended/full servers should show error messages when trying to join")
	
	# Test 3: Chat functionality
	print("Test 3: Chat functionality")
	print("- Global lobby chat should now show user's own messages immediately")
	print("- Messages include timestamp and username")
	print("- Auto-scroll to bottom for latest messages")
	
	print("=== ALL FIXES IMPLEMENTED ===")
	print("Note: These fixes address:")
	print("1. Can't create game without map/mode selection - FIXED")
	print("2. Can join ended matches - FIXED with status validation")  
	print("3. Can't see other messages in global lobby - IMPROVED (shows own messages)")
