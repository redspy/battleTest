extends Node
## Autoload: 두 폰의 1:1 세션. 방을 만든 폰이 상태의 원본(호스트)이고, 참가한 폰은 보기 + 입력만 한다.
## 같은 Wi-Fi 에서 ENet 으로 연결한다. 호스트는 UDP 방송으로 자기를 알리고, 참가 쪽은 목록에서 고르거나 주소를 직접 넣는다.
## 혼자 하기(solo) 는 연결 없이 자리 1 을 AI 가 맡는다.
##
## 흐름: lobby(팀 고르기·준비) → pick(n 마리 비공개 선출) → battle(1:1 대전)
## 화면은 view 와 changed 신호만 본다. 입력은 send(msg).
##   msg: {t:"team", id} {t:"ready", v} {t:"count", n} {t:"picks", picks:[번호]} {t:"act", a} {t:"again"}

signal changed
signal closed(reason: String)
signal hosts_changed

const SET_ID := "pokemon"
const BATTLE_MODE := "battle"
const BEACON := "BT5|pokemon|battle"

const PORT := 47316
const BEACON_PORT := 47311

var view := {}             # 내 자리에서 본 상태 (화면이 읽는다)
var seat := 0
var role := ""             # host / join / solo / ""
var status := ""           # 연결 상태 글자
var found_hosts := {}      # 주소 → 마지막 발견 시각

var _s := {}               # 호스트의 실제 상태
var _beacon: PacketPeerUDP
var _listen: PacketPeerUDP
var _beacon_t := 0.0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func():
		status = "연결됨"
		changed.emit())
	multiplayer.connection_failed.connect(func(): _close("연결하지 못했습니다"))
	multiplayer.server_disconnected.connect(func(): _close("방이 닫혔습니다"))

func is_host() -> bool:
	return role == "host" or role == "solo"

func local_addresses() -> Array:
	if "--shots" in OS.get_cmdline_user_args():
		return ["127.0.0.1"]
	var out := []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out

# ───────────── 시작 / 끝 ─────────────

func start(p_role: String) -> String:
	leave()
	role = p_role
	seat = 0
	if role == "host":
		var peer := ENetMultiplayerPeer.new()
		var screenshot_run := "--shots" in OS.get_cmdline_user_args()
		if screenshot_run:
			peer.set_bind_ip("127.0.0.1")
		var err := peer.create_server(0 if screenshot_run else PORT, 1)
		if err != OK:
			role = ""
			return "방을 만들지 못했습니다 (%s)" % error_string(err)
		multiplayer.multiplayer_peer = peer
		if not screenshot_run:
			_beacon = PacketPeerUDP.new()
			_beacon.set_broadcast_enabled(true)
			_beacon.set_dest_address("255.255.255.255", BEACON_PORT)
		status = "상대를 기다리는 중"
	if is_host():
		_s = { "phase": "lobby", "count": 3, "solo": role == "solo", "allowGmax": false,
			"players": [_new_player("나" if role == "solo" else "방장"), _new_player("AI" if role == "solo" else "")], "battle": {}, "events": [] }
		_s["players"][0]["here"] = true
		if role == "solo":
			_s["players"][1]["here"] = true
			_s["players"][1]["team"] = BBot.pick_team(SET_ID)
			_s["players"][1]["ready"] = true
			status = "혼자 하기"
		_push([])
	return ""

func _new_player(name: String) -> Dictionary:
	return { "name": name, "here": false, "team": "", "ready": false, "picks": [] }

func join(address: String) -> String:
	leave()
	role = "join"
	seat = 1
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		role = ""
		return "연결하지 못했습니다 (%s)" % error_string(err)
	multiplayer.multiplayer_peer = peer
	status = "%s 에 연결하는 중" % address
	return ""

func scan(on: bool) -> void:
	if "--shots" in OS.get_cmdline_user_args():
		return
	if on and _listen == null:
		_listen = PacketPeerUDP.new()
		if _listen.bind(BEACON_PORT) != OK:
			_listen = null
		found_hosts.clear()
	elif not on and _listen != null:
		_listen.close()
		_listen = null

func leave() -> void:
	scan(false)
	if _beacon:
		_beacon.close()
		_beacon = null
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = ""
	status = ""
	view = {}
	_s = {}

func _close(reason: String) -> void:
	leave()
	closed.emit(reason)

func _process(delta: float) -> void:
	if _beacon and _s.get("phase", "") == "lobby" and not _s["players"][1]["here"]:
		_beacon_t -= delta
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			_beacon.put_packet(BEACON.to_utf8_buffer())
	if _listen:
		var dirty := false
		while _listen.get_available_packet_count() > 0:
			var announcement := _listen.get_packet().get_string_from_utf8()
			var ip := _listen.get_packet_ip()
			if announcement == BEACON and ip != "":
				dirty = dirty or not found_hosts.has(ip)
				found_hosts[ip] = Time.get_ticks_msec()
		if dirty:
			hosts_changed.emit()

func _on_peer_connected(id: int) -> void:
	if role != "host":
		return
	if _s["players"][1]["here"]:
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id)
		return
	_s["players"][1]["here"] = true
	_s["players"][1]["name"] = "참가자"
	_s["peer"] = id
	status = "상대가 들어왔습니다"
	_push([])

func _on_peer_disconnected(id: int) -> void:
	if role != "host" or int(_s.get("peer", 0)) != id:
		return
	# 상대가 나가면 로비로 돌아가 다시 기다린다
	_s["players"][1] = _new_player("")
	_s["players"][0]["ready"] = false
	_s["players"][0]["picks"] = []
	_s["phase"] = "lobby"
	_s["battle"] = {}
	_s.erase("peer")
	status = "상대가 나갔습니다. 다시 기다리는 중"
	_push([])

# ───────────── 입력 ─────────────

func send(msg: Dictionary) -> void:
	if is_host():
		_handle(0, msg)
	elif role == "join":
		_c2h.rpc_id(1, msg)

@rpc("any_peer", "call_remote", "reliable")
func _c2h(msg: Dictionary) -> void:
	if role == "host" and multiplayer.get_remote_sender_id() == int(_s.get("peer", 0)):
		_handle(1, msg)

@rpc("authority", "call_remote", "reliable")
func _h2c(v: Dictionary) -> void:
	if v.get("set") != SET_ID or v.get("mode") != BATTLE_MODE:
		_close.call_deferred("대회 팀 1:1 대전 방에만 참가할 수 있습니다")
		return
	view = v
	changed.emit()

func _handle(who: int, msg: Dictionary) -> void:
	if _s.is_empty():
		return
	var p: Dictionary = _s["players"][who]
	var events := []
	match str(msg.get("t", "")):
		"team":
			if _s["phase"] == "lobby" and not Data.team(SET_ID, str(msg.get("id", ""))).is_empty():
				p["team"] = str(msg["id"])
				p["ready"] = false
		"count":
			if _s["phase"] == "lobby" and who == 0 and int(msg.get("n", 0)) in [3, 4]:
				_s["count"] = int(msg["n"])
		"gmax":
			if _s["phase"] == "lobby" and who == 0:
				_s["allowGmax"] = msg.get("enabled") == true
		"ready":
			if _s["phase"] == "lobby" and p["team"] != "":
				p["ready"] = bool(msg.get("v", false))
				if _s["players"][0]["ready"] and _s["players"][1]["ready"] and _s["players"][1]["here"]:
					_s["phase"] = "pick"
					for q in _s["players"]:
						q["picks"] = []
					if _s["solo"]:
						_s["players"][1]["picks"] = BBot.pick_members(SET_ID, _s["players"][1]["team"], _s["players"][0]["team"], int(_s["count"]))
		"picks":
			var picks: Array = msg.get("picks", [])
			if _s["phase"] == "pick" and (p["picks"] as Array).is_empty() and _valid_picks(picks):
				p["picks"] = picks.map(func(x): return int(x))
				if not (_s["players"][0]["picks"] as Array).is_empty() and not (_s["players"][1]["picks"] as Array).is_empty():
					_begin()
		"act":
			if _s["phase"] == "battle":
				events = BEngine.submit(_s["battle"], who, msg.get("a", {}))
				events += _bot_moves()
		"again":
			if _s["phase"] == "battle" and _s["battle"].get("over", false):
				_s["phase"] = "lobby"
				_s["battle"] = {}
				for i in 2:
					_s["players"][i]["ready"] = _s["solo"] and i == 1
					_s["players"][i]["picks"] = []
	_push(events)

func _valid_picks(picks: Array) -> bool:
	if picks.size() != int(_s["count"]):
		return false
	var seen := {}
	for x in picks:
		if int(x) < 0 or int(x) >= 6 or seen.has(int(x)):
			return false
		seen[int(x)] = true
	return true

func _begin() -> void:
	var ids := []
	for i in 2:
		var members: Array = Data.team(SET_ID, _s["players"][i]["team"])["members"]
		ids.append((_s["players"][i]["picks"] as Array).map(func(x): return members[x]))
	_s["battle"] = BEngine.create(ids[0], ids[1], randi(), SET_ID, _s["allowGmax"])
	_s["phase"] = "battle"

## 혼자 하기: AI 가 고를 차례면 고른다 (연쇄 처리)
func _bot_moves() -> Array:
	var events := []
	if not _s["solo"]:
		return events
	var guard := 0
	while BEngine.waiting_for(_s["battle"], 1) and guard < 4:
		guard += 1
		events += BEngine.submit(_s["battle"], 1, BBot.choose(_s["battle"], 1))
	return events

# ───────────── 보기 만들기 ─────────────

func _view_for(who: int, events: Array) -> Dictionary:
	var players := []
	for i in 2:
		var p: Dictionary = _s["players"][i]
		players.append({ "name": p["name"], "here": p["here"], "team": p["team"], "ready": p["ready"],
			"picked": not (p["picks"] as Array).is_empty(), "picks": p["picks"] if i == who else [] })
	var v := { "set": SET_ID, "mode": BATTLE_MODE, "phase": _s["phase"], "count": _s["count"], "solo": _s["solo"], "allowGmax": _s["allowGmax"],
		"seat": who, "players": players, "events": events }
	if _s["phase"] == "battle":
		v["battle"] = BEngine.view(_s["battle"], who)
	return v

func _push(events: Array) -> void:
	if role == "solo" and _s["phase"] == "battle" and events.is_empty():
		events = _bot_moves()
	view = _view_for(0, events)
	if role == "host" and _s.has("peer"):
		_h2c.rpc_id(int(_s["peer"]), _view_for(1, events))
	changed.emit()
