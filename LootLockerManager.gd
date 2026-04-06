extends Node

var api_key = "dev_d8683b55b5f9497a9fd821b574632d66"
var player_session_token = ""
var player_id = ""

func login_guest():
	var http = HTTPRequest.new()
	add_child(http)
	
	var url = "https://api.lootlocker.io/game/v1/player/login/guest"
	var body = JSON.stringify({
		"game_key": api_key,
		"player_identifier": OS.get_unique_id() # Unique to each player's hardware
	})
	
	http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	var response = await http.request_completed
	var json = JSON.parse_string(response[3].get_string_from_utf8())
	
	if json.has("session_token"):
		player_session_token = json.session_token
		player_id = str(json.player_id)
		print("SUCCESS: Logged into LootLocker! Player ID: ", player_id)
	else:
		print("LootLocker Login Failed: ", json)
	
	http.queue_free()
