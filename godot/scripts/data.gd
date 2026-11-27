extends Node
## Autoload: res://data/<세트>/ 의 species / teams / moves / sprites (/ rules) 를 읽는다.
## 대회 팀과 1:1 대전 데이터를 읽는다.
## (데이터와 그림은 `node scripts/build-sprites.mjs` 가 만든다)

const SETS := ["pokemon"]

const STAT_LABELS := {
	"hp": "HP", "atk": "공격", "def": "방어",
	"spa": "특수공격", "spd": "특수방어", "spe": "스피드",
}
const RANK_STATS := ["atk", "def", "spa", "spd", "spe"]
const BATTLE_RANKS := ["atk", "def", "spa", "spd", "spe", "accuracy", "evasion"]

const TYPE_COLOR := {
	"노말": Color(0.66, 0.66, 0.58), "불꽃": Color(0.95, 0.50, 0.26), "물": Color(0.38, 0.58, 0.95), "전기": Color(0.97, 0.82, 0.25),
	"풀": Color(0.45, 0.78, 0.38), "얼음": Color(0.58, 0.85, 0.86), "격투": Color(0.80, 0.33, 0.30), "독": Color(0.66, 0.38, 0.72),
	"땅": Color(0.86, 0.72, 0.42), "비행": Color(0.62, 0.66, 0.96), "에스퍼": Color(0.97, 0.42, 0.58), "벌레": Color(0.66, 0.74, 0.24),
	"바위": Color(0.72, 0.64, 0.38), "고스트": Color(0.50, 0.42, 0.68), "드래곤": Color(0.48, 0.38, 0.97), "악": Color(0.50, 0.42, 0.38),
	"강철": Color(0.72, 0.72, 0.82), "페어리": Color(0.94, 0.62, 0.78),
	"화염": Color(0.96, 0.52, 0.24), "수풀": Color(0.42, 0.78, 0.42), "대지": Color(0.74, 0.60, 0.42), "번개": Color(0.72, 0.58, 0.96),
	"물결": Color(0.36, 0.66, 0.96), "서리": Color(0.62, 0.86, 0.94),
}

var sets := {}
var battle_rules: Dictionary
var load_error := ""

func _ready() -> void:
	battle_rules = _json("res://data/pokemon/battle_rules.json")
	for id in SETS:
		_load(id)

func _json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())

func _load(id: String) -> void:
	var base := "res://data/%s/" % id
	var sp = _json(base + "species.json")
	var tm = _json(base + "teams.json")
	var mv = _json(base + "moves.json")
	var spr = _json(base + "sprites.json")
	if not (sp is Dictionary and tm is Dictionary and mv is Dictionary and spr is Dictionary):
		load_error = "%s 데이터를 읽을 수 없습니다" % id
		push_error(load_error)
		return
	var by_id := {}
	for s in sp["species"]:
		by_id[s["id"]] = s
	var rules = _json(base + "rules.json")
	sets[id] = { "id": id, "species": by_id, "order": sp["species"], "info": tm, "teams": tm["teams"], "moves": mv.get("moves", {}),
		"practice_sets": mv.get("practiceSets", {}), "items": mv.get("items", {}), "abilities": mv.get("abilities", {}), "sprites": spr, "rules": rules if rules is Dictionary else {} }
	print("[Data] %s: %d종, %d팀, 그림 %d개" % [id, by_id.size(), tm["teams"].size(), spr.size()])

func species(set_id: String, id: String) -> Dictionary:
	return sets[set_id]["species"].get(id, {})

func team(set_id: String, id: String) -> Dictionary:
	for t in sets[set_id]["teams"]:
		if t["id"] == id:
			return t
	return {}

## 폼 정보. 그림이 없는 폼은 fallback 폼의 그림을 쓴다 (반환값의 "file").
func form(set_id: String, species_id: String, form_id: String) -> Dictionary:
	var sp := species(set_id, species_id)
	var found := {}
	for f in sp.get("forms", []):
		if f["id"] == form_id:
			found = f.duplicate()
	if found.is_empty() and not sp.is_empty():
		found = (sp["forms"][0] as Dictionary).duplicate()
	if found.get("file") == null and found.has("fallback"):
		for f in sp["forms"]:
			if f["id"] == found["fallback"]:
				found["file"] = f["file"]
				found["noArt"] = true
	return found

func battle_stats(base_stats: Dictionary, training: Dictionary) -> Dictionary:
	var points: Dictionary = training.get("points", {})
	var stats := { "hp": int(base_stats["hp"]) + int(points.get("hp", 0)) + 75 }
	for key in RANK_STATS:
		var alignment := 110 if training.get("boost") == key else (90 if training.get("reduce") == key else 100)
		stats[key] = floori((int(base_stats[key]) + int(points.get(key, 0)) + 20) * alignment / 100.0)
	return stats

func types(set_id: String, species_id: String, form_id: String) -> Array:
	var f := form(set_id, species_id, form_id)
	if f.has("types"):
		return f["types"]
	return species(set_id, species_id).get("types", [])

## 이름 (폼이 기본이 아니면 "메가 리자몽" 처럼 폼을 붙인다)
func display_name(set_id: String, species_id: String, form_id: String) -> String:
	var sp := species(set_id, species_id)
	var f := form(set_id, species_id, form_id)
	var label := str(f.get("label", ""))
	if form_id == "base" or label in ["기본", "수컷", "암컷"]:
		return str(sp.get("ko", species_id))
	return "%s %s" % [sp.get("ko", species_id), label]

func sprite_meta(set_id: String, file: String, thumb: bool) -> Dictionary:
	var m: Dictionary = sets[set_id]["sprites"].get(file, {})
	return m.get("thumb" if thumb else "big", {})

func sprite_path(set_id: String, file: String, thumb: bool) -> String:
	return "res://sprites/%s/%s%s.webp" % [set_id, file, "_t" if thumb else ""]

func type_color(t: String) -> Color:
	return TYPE_COLOR.get(t, Color(0.7, 0.7, 0.7))

func move(set_id: String, id: String) -> Dictionary:
	return sets[set_id]["moves"].get(id, {})

## 이 종을 쓰는 팀 수
func usage(set_id: String, species_id: String) -> int:
	var n := 0
	for t in sets[set_id]["teams"]:
		for m in t["members"]:
			if m["species"] == species_id:
				n += 1
	return n
