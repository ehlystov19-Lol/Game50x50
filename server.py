import asyncio
import json
import math
import random
import time
import sys
import io
from aiohttp import web

# Fix stdout UTF-8 encoding for Windows console
if sys.platform == 'win32':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

GRID_SIZE = 50
TOTAL_TILES = GRID_SIZE * GRID_SIZE

KINGDOM_HP_LEVELS = [100, 125, 150, 200, 500]

MILL_SCORE_LEVELS = [
    1, 2, 4, 6, 8, 10, 12, 15, 18, 22, 
    25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 
    75, 80, 85, 90, 100
]

BARRACKS_SPAWN_INTERVALS = [0.6, 0.5, 0.42, 0.37, 0.3, 0.27, 0.24, 0.2, 0.15, 0.12, 0.1]
WALL_HP_LEVELS = [int(2 + (i / 99) ** 1.8 * 998) for i in range(100)]
WARRIOR_LEVELS = [round(1 + (i / 49) * 74) for i in range(50)]

COST_KINGDOM = 10.0
COST_MILL = 2.0
COST_WALL = 0.1
COST_TOWER = 5.0
COST_BARRACKS = 8.0

PLAYER_COLORS = ['#00f3ff', '#ff007f', '#39ff14', '#ffe600', '#9d00ff', '#ff5500', '#00ffaa', '#ff00aa']

random.seed(42)
gold_mine_indices = set(random.sample(range(TOTAL_TILES), 70))

map_tiles = []
for i in range(TOTAL_TILES):
    map_tiles.append({
        "id": i,
        "x": i % GRID_SIZE,
        "y": i // GRID_SIZE,
        "isGoldMine": (i in gold_mine_indices),
        "building": None
    })

players = {}
clients = {}
warriors = []
projectiles = []

bullet_id_counter = 0
warrior_id_counter = 0

def calculate_leaderboard():
    board = []
    for p_id, p in players.items():
        board.append({
            "id": p_id,
            "name": p["name"],
            "color": p["color"],
            "score": int(p["score"]),
            "gold": round(p["gold"], 1),
            "hasKingdom": p["hasKingdom"],
            "warriorLevel": p["warriorLevel"] + 1
        })
    board.sort(key=lambda x: x["score"], reverse=True)
    return board

async def broadcast(message_dict):
    if not clients:
        return
    payload = json.dumps(message_dict)
    disconnected = []
    for ws in list(clients.keys()):
        try:
            await ws.send_str(payload)
        except Exception:
            disconnected.append(ws)
    for ws in disconnected:
        if ws in clients:
            del clients[ws]

async def websocket_handler(request):
    ws = web.WebSocketResponse()
    await ws.prepare(request)

    player_id = f"p_{id(ws)}"
    clients[ws] = player_id

    try:
        async for msg in ws:
            if msg.type == web.WSMsgType.TEXT:
                data = json.loads(msg.data)
                event = data.get("type")

                if event == "ping_check":
                    await ws.send_str(json.dumps({
                        "type": "pong_check",
                        "clientTimestamp": data.get("clientTimestamp")
                    }))

                elif event == "join_game":
                    name = str(data.get("name", "Правитель")).strip()[:15] or "Правитель"
                    color = data.get("color", random.choice(PLAYER_COLORS))

                    players[player_id] = {
                        "id": player_id,
                        "name": name,
                        "color": color,
                        "gold": 15.0,
                        "score": 0,
                        "lastGoldClick": 0,
                        "hasKingdom": False,
                        "kingdomTile": None,
                        "warriorLevel": 0
                    }

                    await ws.send_str(json.dumps({
                        "type": "init_game",
                        "id": player_id,
                        "gridSize": GRID_SIZE,
                        "tiles": map_tiles,
                        "leaderboard": calculate_leaderboard()
                    }))

                    await broadcast({
                        "type": "chat_message",
                        "sender": "SYSTEM",
                        "text": f"👑 {name} основать пытается королевство!",
                        "color": "#39ff14"
                    })

                elif event == "mine_gold":
                    if player_id not in players:
                        continue
                    p = players[player_id]
                    now = time.time()

                    if now - p["lastGoldClick"] >= 0.58:
                        p["lastGoldClick"] = now
                        p["gold"] += 1.0
                        await ws.send_str(json.dumps({
                            "type": "gold_mined",
                            "gold": round(p["gold"], 1)
                        }))

                elif event == "build":
                    if player_id not in players:
                        continue
                    p = players[player_id]
                    tile_id = data.get("tileId")
                    b_type = data.get("buildingType")

                    if tile_id is None or not (0 <= tile_id < TOTAL_TILES):
                        continue

                    tile = map_tiles[tile_id]
                    if tile["building"] is not None:
                        continue

                    if b_type == 'kingdom':
                        if p["gold"] < COST_KINGDOM: continue
                        if p["hasKingdom"]: continue
                        
                        p["gold"] -= COST_KINGDOM
                        p["hasKingdom"] = True
                        p["kingdomTile"] = tile_id

                        tile["building"] = {
                            "type": "kingdom",
                            "ownerId": player_id,
                            "ownerName": p["name"],
                            "color": p["color"],
                            "level": 0,
                            "hp": KINGDOM_HP_LEVELS[0],
                            "maxHp": KINGDOM_HP_LEVELS[0]
                        }

                    else:
                        if not p["hasKingdom"]: continue

                        k_tile = map_tiles[p["kingdomTile"]]
                        dist_x = abs(tile["x"] - k_tile["x"])
                        dist_y = abs(tile["y"] - k_tile["y"])
                        if dist_x > 7 or dist_y > 7: continue

                        cost = 0
                        if b_type == 'mill': cost = COST_MILL
                        elif b_type == 'wall': cost = COST_WALL
                        elif b_type == 'tower': cost = COST_TOWER
                        elif b_type == 'barracks': cost = COST_BARRACKS
                        else: continue

                        if p["gold"] < cost: continue

                        p["gold"] -= cost

                        init_hp = 100
                        if b_type == 'wall': init_hp = WALL_HP_LEVELS[0]
                        elif b_type == 'mill': init_hp = 50
                        elif b_type == 'tower': init_hp = 120
                        elif b_type == 'barracks': init_hp = 150

                        tile["building"] = {
                            "type": b_type,
                            "ownerId": player_id,
                            "ownerName": p["name"],
                            "color": p["color"],
                            "level": 0,
                            "hp": init_hp,
                            "maxHp": init_hp,
                            "lastSpawnTime": time.time(),
                            "lastIncomeTime": time.time()
                        }

                    await broadcast({
                        "type": "tile_updated",
                        "tile": tile,
                        "playerGold": round(p["gold"], 1),
                        "leaderboard": calculate_leaderboard()
                    })

                elif event == "upgrade_building":
                    if player_id not in players: continue
                    p = players[player_id]
                    tile_id = data.get("tileId")
                    if tile_id is None or not (0 <= tile_id < TOTAL_TILES): continue

                    tile = map_tiles[tile_id]
                    b = tile["building"]
                    if not b or b["ownerId"] != player_id: continue

                    b_type = b["type"]
                    upgraded = False

                    if b_type == "kingdom":
                        if b["level"] < len(KINGDOM_HP_LEVELS) - 1:
                            cost = 15.0 * (b["level"] + 1)
                            if p["gold"] >= cost:
                                p["gold"] -= cost
                                b["level"] += 1
                                new_hp = KINGDOM_HP_LEVELS[b["level"]]
                                b["maxHp"] = new_hp
                                b["hp"] = new_hp
                                upgraded = True

                    elif b_type == "mill":
                        if b["level"] < len(MILL_SCORE_LEVELS) - 1:
                            cost = 3.0 * (b["level"] + 1)
                            if p["gold"] >= cost:
                                p["gold"] -= cost
                                b["level"] += 1
                                upgraded = True

                    elif b_type == "barracks":
                        if b["level"] < len(BARRACKS_SPAWN_INTERVALS) - 1:
                            cost = 10.0 * (b["level"] + 1)
                            if p["gold"] >= cost:
                                p["gold"] -= cost
                                b["level"] += 1
                                upgraded = True

                    elif b_type == "wall":
                        if b["level"] < len(WALL_HP_LEVELS) - 1:
                            cost = 0.2 * (b["level"] + 1)
                            if p["gold"] >= cost:
                                p["gold"] -= cost
                                b["level"] += 1
                                new_hp = WALL_HP_LEVELS[b["level"]]
                                b["maxHp"] = new_hp
                                b["hp"] = new_hp
                                upgraded = True

                    if upgraded:
                        await broadcast({
                            "type": "tile_updated",
                            "tile": tile,
                            "playerGold": round(p["gold"], 1),
                            "leaderboard": calculate_leaderboard()
                        })

                elif event == "upgrade_warriors":
                    if player_id not in players: continue
                    p = players[player_id]
                    if p["warriorLevel"] < len(WARRIOR_LEVELS) - 1:
                        cost = 5.0 * (p["warriorLevel"] + 1)
                        if p["gold"] >= cost:
                            p["gold"] -= cost
                            p["warriorLevel"] += 1
                            await ws.send_str(json.dumps({
                                "type": "warrior_upgraded",
                                "level": p["warriorLevel"] + 1,
                                "gold": round(p["gold"], 1),
                                "stats": {
                                    "hp": WARRIOR_LEVELS[p["warriorLevel"]],
                                    "damage": WARRIOR_LEVELS[p["warriorLevel"]]
                                }
                            }))

                elif event == "send_chat":
                    if player_id in players:
                        p = players[player_id]
                        text = str(data.get("text", "")).strip()[:80]
                        if text:
                            await broadcast({
                                "type": "chat_message",
                                "sender": p["name"],
                                "text": text,
                                "color": p["color"]
                            })

    finally:
        if ws in clients: del clients[ws]
        if player_id in players:
            del players[player_id]
            await broadcast({
                "type": "leaderboard_update",
                "leaderboard": calculate_leaderboard()
            })

    return ws

async def game_simulation_loop():
    global warrior_id_counter, bullet_id_counter
    while True:
        await asyncio.sleep(0.05)
        now = time.time()

        for tile in map_tiles:
            b = tile["building"]
            if b and b["type"] == "mill":
                if now - b.get("lastIncomeTime", 0) >= 1.5:
                    b["lastIncomeTime"] = now
                    owner = players.get(b["ownerId"])
                    if owner:
                        score_gain = MILL_SCORE_LEVELS[min(b["level"], len(MILL_SCORE_LEVELS) - 1)]
                        owner["score"] += score_gain

        for tile in map_tiles:
            b = tile["building"]
            if b and b["type"] == "barracks":
                interval = BARRACKS_SPAWN_INTERVALS[min(b["level"], len(BARRACKS_SPAWN_INTERVALS) - 1)]
                if now - b.get("lastSpawnTime", 0) >= interval:
                    b["lastSpawnTime"] = now
                    owner = players.get(b["ownerId"])
                    if owner:
                        enemy_kingdoms = [
                            t for t in map_tiles 
                            if t["building"] and t["building"]["type"] == "kingdom" and t["building"]["ownerId"] != owner["id"]
                        ]
                        if enemy_kingdoms:
                            target_k = random.choice(enemy_kingdoms)
                            w_lvl = owner["warriorLevel"]
                            w_stat = WARRIOR_LEVELS[w_lvl]
                            warrior_id_counter += 1

                            warriors.append({
                                "id": f"w_{warrior_id_counter}",
                                "ownerId": owner["id"],
                                "x": tile["x"] + 0.5,
                                "y": tile["y"] + 0.5,
                                "targetX": target_k["x"] + 0.5,
                                "targetY": target_k["y"] + 0.5,
                                "hp": w_stat,
                                "maxHp": w_stat,
                                "damage": w_stat,
                                "speed": 0.08,
                                "color": owner["color"]
                            })

        for w in list(warriors):
            dx = w["targetX"] - w["x"]
            dy = w["targetY"] - w["y"]
            dist = math.hypot(dx, dy)

            if dist < 0.2:
                tx = int(w["targetX"])
                ty = int(w["targetY"])
                target_tile_idx = ty * GRID_SIZE + tx
                if 0 <= target_tile_idx < TOTAL_TILES:
                    target_tile = map_tiles[target_tile_idx]
                    tb = target_tile["building"]
                    if tb:
                        tb["hp"] -= w["damage"]
                        if tb["hp"] <= 0:
                            k_owner_id = tb["ownerId"]
                            target_tile["building"] = None
                            if k_owner_id in players:
                                players[k_owner_id]["hasKingdom"] = False
                                players[k_owner_id]["kingdomTile"] = None
                            
                            asyncio.create_task(broadcast({
                                "type": "chat_message",
                                "sender": "WAR",
                                "text": f"💥 Королевство игрока {tb['ownerName']} уничтожено!",
                                "color": "#ff007f"
                            }))

                        asyncio.create_task(broadcast({
                            "type": "tile_updated",
                            "tile": target_tile,
                            "leaderboard": calculate_leaderboard()
                        }))

                warriors.remove(w)
                continue

            w["x"] += (dx / dist) * w["speed"]
            w["y"] += (dy / dist) * w["speed"]

            t_x = int(w["x"])
            t_y = int(w["y"])
            curr_tile_idx = t_y * GRID_SIZE + t_x
            if 0 <= curr_tile_idx < TOTAL_TILES:
                c_tile = map_tiles[curr_tile_idx]
                cb = c_tile["building"]
                if cb and cb["type"] == "wall" and cb["ownerId"] != w["ownerId"]:
                    cb["hp"] -= w["damage"]
                    if cb["hp"] <= 0:
                        c_tile["building"] = None
                    warriors.remove(w)
                    asyncio.create_task(broadcast({
                        "type": "tile_updated",
                        "tile": c_tile
                    }))
                    continue

        for tile in map_tiles:
            b = tile["building"]
            if b and b["type"] == "tower":
                t_x = tile["x"] + 0.5
                t_y = tile["y"] + 0.5

                if now - b.get("lastShootTime", 0) >= 0.4:
                    target_w = None
                    min_d = 6.0
                    for w in warriors:
                        if w["ownerId"] != b["ownerId"]:
                            d = math.hypot(w["x"] - t_x, w["y"] - t_y)
                            if d < min_d:
                                min_d = d
                                target_w = w

                    if target_w:
                        b["lastShootTime"] = now
                        target_w["hp"] -= 15
                        bullet_id_counter += 1
                        projectiles.append({
                            "id": f"p_{bullet_id_counter}",
                            "startX": t_x,
                            "startY": t_y,
                            "targetX": target_w["x"],
                            "targetY": target_w["y"],
                            "color": b["color"],
                            "life": 5
                        })

                        if target_w["hp"] <= 0:
                            if target_w in warriors:
                                warriors.remove(target_w)

        asyncio.create_task(broadcast({
            "type": "game_frame",
            "warriors": warriors,
            "projectiles": projectiles,
            "leaderboard": calculate_leaderboard()
        }))
        projectiles.clear()

def main():
    app = web.Application()
    app.on_startup.append(lambda a: asyncio.create_task(game_simulation_loop()))
    app.router.add_get('/ws', websocket_handler)
    app.router.add_static('/', path='public', show_index=True)

    print("==================================================")
    print("Kingdom Wars Server is READY at http://127.0.0.1:3000")
    print("==================================================")
    
    try:
        web.run_app(app, host='127.0.0.1', port=3000)
    except Exception:
        web.run_app(app, host='0.0.0.0', port=3000)

if __name__ == '__main__':
    main()
