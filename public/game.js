// WebSocket connection setup
const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
const wsUrl = `${wsProtocol}//${window.location.host}/ws`;
let socket = null;

function initWebSocket() {
    socket = new WebSocket(wsUrl);

    socket.onopen = () => {
        console.log("Connected to Kingdom Wars 50x50 Server!");
    };

    socket.onmessage = (event) => {
        try {
            const data = JSON.parse(event.data);
            handleServerEvent(data);
        } catch (err) {
            console.error("Parse error", err);
        }
    };

    socket.onclose = () => {
        setTimeout(initWebSocket, 2000);
    };
}

initWebSocket();

function sendWS(type, payload = {}) {
    if (socket && socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify({ type: type, ...payload }));
    }
}

// Canvas Setup & Camera Control
const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');

function resizeCanvas() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
}
window.addEventListener('resize', resizeCanvas);
resizeCanvas();

const TILE_SIZE = 40; // 40px per tile in world space
const GRID_SIZE = 50;
const WORLD_PIXEL_SIZE = GRID_SIZE * TILE_SIZE; // 2000 x 2000 px

let cameraX = WORLD_PIXEL_SIZE / 2 - canvas.width / 2;
let cameraY = WORLD_PIXEL_SIZE / 2 - canvas.height / 2;
let zoom = 1.0;

let isDragging = false;
let dragStartX = 0;
let dragStartY = 0;

// Web Audio API Synthesizer
const audioCtx = new (window.AudioContext || window.webkitAudioContext)();

function playSound(type) {
    if (audioCtx.state === 'suspended') audioCtx.resume();
    const osc = audioCtx.createOscillator();
    const gain = audioCtx.createGain();
    osc.connect(gain);
    gain.connect(audioCtx.destination);
    const now = audioCtx.currentTime;

    if (type === 'gold') {
        osc.type = 'sine';
        osc.frequency.setValueAtTime(987, now);
        osc.frequency.exponentialRampToValueAtTime(1318, now + 0.1);
        gain.gain.setValueAtTime(0.2, now);
        gain.gain.linearRampToValueAtTime(0.01, now + 0.1);
        osc.start(now); osc.stop(now + 0.1);
    } else if (type === 'build') {
        osc.type = 'triangle';
        osc.frequency.setValueAtTime(300, now);
        osc.frequency.exponentialRampToValueAtTime(600, now + 0.15);
        gain.gain.setValueAtTime(0.25, now);
        gain.gain.linearRampToValueAtTime(0.01, now + 0.15);
        osc.start(now); osc.stop(now + 0.15);
    } else if (type === 'upgrade') {
        osc.type = 'sawtooth';
        osc.frequency.setValueAtTime(440, now);
        osc.frequency.exponentialRampToValueAtTime(880, now + 0.2);
        gain.gain.setValueAtTime(0.2, now);
        gain.gain.linearRampToValueAtTime(0.01, now + 0.2);
        osc.start(now); osc.stop(now + 0.2);
    }
}

// Game State Variables
let myId = null;
let tiles = [];
let warriors = [];
let projectiles = [];
let leaderboard = [];
let selectedTool = 'select'; // 'select', 'kingdom', 'mill', 'wall', 'tower', 'barracks'
let selectedTileId = null;
let hoverTileId = null;

let myGold = 15.0;
let myScore = 0;
let myWarriorLevel = 1;
let myHasKingdom = false;
let myKingdomTile = null;

const KINGDOM_HP_LEVELS = [100, 125, 150, 200, 500];
const MILL_SCORE_LEVELS = [1, 2, 4, 6, 8, 10, 12, 15, 18, 22, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 100];
const BARRACKS_SPAWN_INTERVALS = [0.6, 0.5, 0.42, 0.37, 0.3, 0.27, 0.24, 0.2, 0.15, 0.12, 0.1];
const WARRIOR_LEVELS = [round(1 + (i / 49) * 74) for (let i = 0; i < 50; i++)];
function round(v) { return Math.round(v); }

// UI Elements
const loginModal = document.getElementById('login-modal');
const gameApp = document.getElementById('game-app');
const loginForm = document.getElementById('login-form');
const playerNameInput = document.getElementById('player-name');
const colorOpts = document.querySelectorAll('.color-opt');

const goldVal = document.getElementById('gold-val');
const scoreVal = document.getElementById('score-val');
const goldBtn = document.getElementById('btn-gold-mine');
const goldCdOverlay = document.getElementById('gold-cd-overlay');

const btnUpgradeWarriors = document.getElementById('btn-upgrade-warriors');
const warriorLvlSpan = document.getElementById('warrior-lvl');
const warriorStatSpan = document.getElementById('warrior-stat');
const warriorCostSpan = document.getElementById('warrior-cost');

const buildBtns = document.querySelectorAll('.build-btn');
const inspectorPanel = document.getElementById('inspector-panel');
const inspectTitle = document.getElementById('inspect-title');
const inspectOwner = document.getElementById('inspect-owner');
const inspectLevel = document.getElementById('inspect-level');
const inspectHpBar = document.getElementById('inspect-hp-bar');
const inspectHpVal = document.getElementById('inspect-hp-val');
const btnUpgradeBuilding = document.getElementById('btn-upgrade-building');
const inspectUpgradeCost = document.getElementById('inspect-upgrade-cost');

const leaderboardUL = document.getElementById('leaderboard-ul');
const chatMessages = document.getElementById('chat-messages');
const chatForm = document.getElementById('chat-form');
const chatInput = document.getElementById('chat-input');
const pingTag = document.getElementById('ping-tag');

let selectedColor = '#00f3ff';

colorOpts.forEach(opt => {
    opt.addEventListener('click', () => {
        colorOpts.forEach(c => c.classList.remove('active'));
        opt.classList.add('active');
        selectedColor = opt.dataset.color;
    });
});

loginForm.addEventListener('submit', (e) => {
    e.preventDefault();
    const name = playerNameInput.value.trim();
    if (!name) return;

    sendWS('join_game', { name: name, color: selectedColor });
    loginModal.classList.add('hidden');
    gameApp.classList.remove('hidden');
});

// Building Selection Palette
buildBtns.forEach(btn => {
    btn.addEventListener('click', () => {
        buildBtns.forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        selectedTool = btn.dataset.type;
    });
});

// Gold Mining Click Cooldown
let canMineGold = true;
goldBtn.addEventListener('click', () => {
    if (canMineGold) {
        canMineGold = false;
        sendWS('mine_gold');
        playSound('gold');

        goldCdOverlay.style.transition = 'none';
        goldCdOverlay.style.width = '100%';
        setTimeout(() => {
            goldCdOverlay.style.transition = 'width 0.58s linear';
            goldCdOverlay.style.width = '0%';
        }, 20);

        setTimeout(() => {
            canMineGold = true;
        }, 600);
    }
});

// Warrior Upgrade Button
btnUpgradeWarriors.addEventListener('click', () => {
    sendWS('upgrade_warriors');
});

// Building Upgrade Button
btnUpgradeBuilding.addEventListener('click', () => {
    if (selectedTileId !== null) {
        sendWS('upgrade_building', { tileId: selectedTileId });
        playSound('upgrade');
    }
});

// Server Event Handler
function handleServerEvent(data) {
    switch (data.type) {
        case 'init_game':
            myId = data.id;
            tiles = data.tiles;
            updateLeaderboard(data.leaderboard);
            break;

        case 'gold_mined':
            myGold = data.gold;
            goldVal.textContent = myGold.toFixed(1);
            break;

        case 'tile_updated':
            tiles[data.tile.id] = data.tile;
            if (data.playerGold !== undefined) {
                myGold = data.playerGold;
                goldVal.textContent = myGold.toFixed(1);
            }
            if (data.leaderboard) updateLeaderboard(data.leaderboard);
            if (selectedTileId === data.tile.id) updateInspector(data.tile);
            playSound('build');
            break;

        case 'warrior_upgraded':
            myWarriorLevel = data.level;
            myGold = data.gold;
            goldVal.textContent = myGold.toFixed(1);
            warriorLvlSpan.textContent = myWarriorLevel;
            warriorStatSpan.textContent = data.stats.damage;
            warriorCostSpan.textContent = `${(5.0 * myWarriorLevel).toFixed(0)}g`;
            playSound('upgrade');
            break;

        case 'game_frame':
            warriors = data.warriors;
            projectiles = data.projectiles;
            updateLeaderboard(data.leaderboard);
            break;

        case 'chat_message':
            const div = document.createElement('div');
            div.className = 'chat-msg';
            div.innerHTML = `<span style="color:${data.color}">${escapeHTML(data.sender)}:</span> ${escapeHTML(data.text)}`;
            chatMessages.appendChild(div);
            chatMessages.scrollTop = chatMessages.scrollHeight;
            break;

        case 'pong_check':
            const ping = Date.now() - data.clientTimestamp;
            pingTag.textContent = `PING: ${ping} ms`;
            break;
    }
}

function updateLeaderboard(list) {
    leaderboard = list;
    leaderboardUL.innerHTML = '';
    list.forEach((item, idx) => {
        const li = document.createElement('li');
        if (item.id === myId) {
            li.className = 'me';
            myScore = item.score;
            myHasKingdom = item.hasKingdom;
            scoreVal.textContent = myScore;
        }
        li.innerHTML = `<span>${idx + 1}. <strong style="color:${item.color}">${escapeHTML(item.name)}</strong> ${item.hasKingdom ? '👑' : ''}</span><span>${item.score} очков</span>`;
        leaderboardUL.appendChild(li);
    });
}

function updateInspector(tile) {
    if (!tile || !tile.building) {
        inspectorPanel.classList.add('hidden');
        return;
    }
    const b = tile.building;
    inspectorPanel.classList.remove('hidden');

    const typeNames = { kingdom: '👑 Королевство', mill: '🌾 Мельница', wall: '🛡️ Стена', tower: '🏹 Башня', barracks: '⚔️ Казарма' };
    inspectTitle.textContent = typeNames[b.type] || 'Постройка';
    inspectOwner.textContent = b.ownerName;
    inspectOwner.style.color = b.color;
    inspectLevel.textContent = b.level + 1;

    const hpPct = Math.max(0, (b.hp / b.maxHp) * 100);
    inspectHpBar.style.width = `${hpPct}%`;
    inspectHpVal.textContent = `${Math.round(b.hp)} / ${b.maxHp}`;

    if (b.ownerId === myId) {
        btnUpgradeBuilding.classList.remove('hidden');
        let cost = 0;
        if (b.type === 'kingdom') cost = 15.0 * (b.level + 1);
        else if (b.type === 'mill') cost = 3.0 * (b.level + 1);
        else if (b.type === 'barracks') cost = 10.0 * (b.level + 1);
        else if (b.type === 'wall') cost = 0.2 * (b.level + 1);

        inspectUpgradeCost.textContent = `Цена: ${cost.toFixed(1)}g`;
    } else {
        btnUpgradeBuilding.classList.add('hidden');
    }
}

// Canvas Mouse Controls (Camera Pan & Zoom, Click Place/Select)
canvas.addEventListener('mousedown', (e) => {
    if (e.button === 2 || e.button === 1) { // Right or middle click to drag map
        isDragging = true;
        dragStartX = e.clientX;
        dragStartY = e.clientY;
    } else if (e.button === 0) { // Left click
        const mouseWorld = screenToWorld(e.clientX, e.clientY);
        const tileX = Math.floor(mouseWorld.x / TILE_SIZE);
        const tileY = Math.floor(mouseWorld.y / TILE_SIZE);

        if (tileX >= 0 && tileX < GRID_SIZE && tileY >= 0 && tileY < GRID_SIZE) {
            const tileId = tileY * GRID_SIZE + tileX;
            const tile = tiles[tileId];

            if (selectedTool === 'select') {
                selectedTileId = tileId;
                updateInspector(tile);

                // If clicked gold mine, harvest gold!
                if (tile && tile.isGoldMine && canMineGold) {
                    canMineGold = false;
                    sendWS('mine_gold');
                    playSound('gold');
                    goldCdOverlay.style.transition = 'none';
                    goldCdOverlay.style.width = '100%';
                    setTimeout(() => {
                        goldCdOverlay.style.transition = 'width 0.58s linear';
                        goldCdOverlay.style.width = '0%';
                    }, 20);
                    setTimeout(() => { canMineGold = true; }, 600);
                }

            } else {
                // Place building!
                sendWS('build', { tileId: tileId, buildingType: selectedTool });
            }
        }
    }
});

window.addEventListener('mousemove', (e) => {
    if (isDragging) {
        cameraX -= (e.clientX - dragStartX) / zoom;
        cameraY -= (e.clientY - dragStartY) / zoom;
        dragStartX = e.clientX;
        dragStartY = e.clientY;
    }

    const mouseWorld = screenToWorld(e.clientX, e.clientY);
    const tileX = Math.floor(mouseWorld.x / TILE_SIZE);
    const tileY = Math.floor(mouseWorld.y / TILE_SIZE);

    if (tileX >= 0 && tileX < GRID_SIZE && tileY >= 0 && tileY < GRID_SIZE) {
        hoverTileId = tileY * GRID_SIZE + tileX;
    } else {
        hoverTileId = null;
    }
});

window.addEventListener('mouseup', () => { isDragging = false; });
canvas.addEventListener('contextmenu', e => e.preventDefault()); // Disable right click menu

canvas.addEventListener('wheel', (e) => {
    e.preventDefault();
    const zoomFactor = e.deltaY < 0 ? 1.1 : 0.9;
    zoom = Math.max(0.4, Math.min(2.5, zoom * zoomFactor));
});

function screenToWorld(sx, sy) {
    return {
        x: (sx - canvas.width / 2) / zoom + cameraX + canvas.width / 2,
        y: (sy - canvas.height / 2) / zoom + cameraY + canvas.height / 2
    };
}

// Chat Form
chatForm.addEventListener('submit', (e) => {
    e.preventDefault();
    const text = chatInput.value.trim();
    if (text) {
        sendWS('send_chat', { text: text });
        chatInput.value = '';
    }
    chatInput.blur();
});

function escapeHTML(str) {
    return str.replace(/[&<>'"]/g, tag => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[tag] || tag));
}

// Main Render Loop (60 FPS Canvas)
function render() {
    requestAnimationFrame(render);

    ctx.fillStyle = '#060914';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    ctx.save();
    ctx.translate(canvas.width / 2, canvas.height / 2);
    ctx.scale(zoom, zoom);
    ctx.translate(-cameraX - canvas.width / 2, -cameraY - canvas.height / 2);

    // 1. Draw Map Tiles
    for (let i = 0; i < TOTAL_TILES; i++) {
        const tile = tiles[i];
        if (!tile) continue;

        const px = tile.x * TILE_SIZE;
        const py = tile.y * TILE_SIZE;

        // Base Tile background
        if (tile.isGoldMine) {
            ctx.fillStyle = '#2b2308';
        } else {
            ctx.fillStyle = (tile.x + tile.y) % 2 === 0 ? '#0d1326' : '#0a0f20';
        }
        ctx.fillRect(px, py, TILE_SIZE, TILE_SIZE);

        // Tile Grid Lines
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.04)';
        ctx.strokeRect(px, py, TILE_SIZE, TILE_SIZE);

        // Gold Mine Symbol
        if (tile.isGoldMine) {
            ctx.fillStyle = '#ffe600';
            ctx.shadowColor = '#ffe600';
            ctx.shadowBlur = 10;
            ctx.font = '20px Rajdhani';
            ctx.textAlign = 'center';
            ctx.fillText('🪙', px + TILE_SIZE / 2, py + TILE_SIZE / 2 + 7);
            ctx.shadowBlur = 0;
        }

        // Buildings
        if (tile.building) {
            const b = tile.building;
            ctx.save();

            // Owner Territory glow
            ctx.fillStyle = b.color;
            ctx.globalAlpha = 0.2;
            ctx.fillRect(px + 2, py + 2, TILE_SIZE - 4, TILE_SIZE - 4);
            ctx.globalAlpha = 1.0;

            // Icon
            let icon = '👑';
            if (b.type === 'mill') icon = '🌾';
            else if (b.type === 'wall') icon = '🛡️';
            else if (b.type === 'tower') icon = '🏹';
            else if (b.type === 'barracks') icon = '⚔️';

            ctx.font = '22px Rajdhani';
            ctx.textAlign = 'center';
            ctx.fillText(icon, px + TILE_SIZE / 2, py + TILE_SIZE / 2 + 7);

            // Mini HP Bar
            const barW = TILE_SIZE - 6;
            const barH = 4;
            const hpPct = Math.max(0, b.hp / b.maxHp);
            ctx.fillStyle = 'rgba(0,0,0,0.6)';
            ctx.fillRect(px + 3, py + TILE_SIZE - 6, barW, barH);
            ctx.fillStyle = b.color;
            ctx.fillRect(px + 3, py + TILE_SIZE - 6, barW * hpPct, barH);

            ctx.restore();
        }

        // Selection Highlight
        if (selectedTileId === i) {
            ctx.strokeStyle = '#ffe600';
            ctx.lineWidth = 3;
            ctx.strokeRect(px + 1, py + 1, TILE_SIZE - 2, TILE_SIZE - 2);
        }

        // Hover Highlight
        if (hoverTileId === i) {
            ctx.strokeStyle = '#00f3ff';
            ctx.lineWidth = 2;
            ctx.strokeRect(px, py, TILE_SIZE, TILE_SIZE);
        }
    }

    // 2. Draw Kingdom Territory (15x15 Box) for active player
    const myK = leaderboard.find(l => l.id === myId);
    if (myK && myK.hasKingdom) {
        const kTile = tiles.find(t => t.building && t.building.type === 'kingdom' && t.building.ownerId === myId);
        if (kTile) {
            const minX = Math.max(0, (kTile.x - 7) * TILE_SIZE);
            const minY = Math.max(0, (kTile.y - 7) * TILE_SIZE);
            const size = 15 * TILE_SIZE;

            ctx.strokeStyle = 'rgba(0, 243, 255, 0.4)';
            ctx.lineWidth = 2;
            ctx.setLineDash([8, 8]);
            ctx.strokeRect(minX, minY, size, size);
            ctx.setLineDash([]);
        }
    }

    // 3. Draw Warriors
    warriors.forEach(w => {
        const wx = w.x * TILE_SIZE;
        const wy = w.y * TILE_SIZE;

        ctx.save();
        ctx.fillStyle = w.color;
        ctx.shadowColor = w.color;
        ctx.shadowBlur = 10;
        ctx.beginPath();
        ctx.arc(wx, wy, 10, 0, Math.PI * 2);
        ctx.fill();
        ctx.lineWidth = 2;
        ctx.strokeStyle = '#ffffff';
        ctx.stroke();

        // Mini HP Bar
        const hpPct = Math.max(0, w.hp / w.maxHp);
        ctx.fillStyle = 'rgba(0,0,0,0.6)';
        ctx.fillRect(wx - 12, wy - 18, 24, 3);
        ctx.fillStyle = w.color;
        ctx.fillRect(wx - 12, wy - 18, 24 * hpPct, 3);

        ctx.restore();
    });

    // 4. Draw Projectiles (Tower Shots)
    projectiles.forEach(p => {
        ctx.save();
        ctx.strokeStyle = p.color;
        ctx.shadowColor = p.color;
        ctx.shadowBlur = 15;
        ctx.lineWidth = 3;
        ctx.beginPath();
        ctx.moveTo(p.startX * TILE_SIZE, p.startY * TILE_SIZE);
        ctx.lineTo(p.targetX * TILE_SIZE, p.targetY * TILE_SIZE);
        ctx.stroke();
        ctx.restore();
    });

    ctx.restore();
}

setInterval(() => {
    sendWS('ping_check', { clientTimestamp: Date.now() });
}, 2000);

render();
