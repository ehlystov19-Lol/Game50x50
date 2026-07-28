const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const path = require('path');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: {
        origin: "*",
        methods: ["GET", "POST"]
    }
});

// Serve static frontend files
app.use(express.static(path.join(__dirname, 'public')));

const PORT = process.env.PORT || 3000;

// World constants
const WORLD_SIZE = { width: 3000, height: 3000 };
const MAX_ORBS = 250;

// Game state
const players = {};
const bullets = {};
const orbs = [];
let bulletIdCounter = 0;

// Helper functions
function getRandomColor() {
    const colors = ['#00f3ff', '#ff007f', '#39ff14', '#ffe600', '#9d00ff', '#ff3300'];
    return colors[Math.floor(Math.random() * colors.length)];
}

function spawnOrb() {
    return {
        id: Math.random().toString(36).substring(2, 9),
        x: Math.floor(Math.random() * (WORLD_SIZE.width - 100)) + 50,
        y: Math.floor(Math.random() * (WORLD_SIZE.height - 100)) + 50,
        color: getRandomColor(),
        radius: Math.floor(Math.random() * 4) + 5,
        scoreValue: 10
    };
}

// Initial food spawn
for (let i = 0; i < MAX_ORBS; i++) {
    orbs.push(spawnOrb());
}

io.on('connection', (socket) => {
    console.log(`Player connected: ${socket.id}`);

    // Ping check
    socket.on('ping_check', (clientTimestamp) => {
        socket.emit('pong_check', clientTimestamp);
    });

    // Player joins the game
    socket.on('join_game', (data) => {
        const name = (data.name || 'Neon Fighter').trim().substring(0, 15);
        const color = data.color || '#00f3ff';

        players[socket.id] = {
            id: socket.id,
            name: name,
            color: color,
            x: Math.floor(Math.random() * (WORLD_SIZE.width - 400)) + 200,
            y: Math.floor(Math.random() * (WORLD_SIZE.height - 400)) + 200,
            radius: 24,
            speed: 5,
            health: 100,
            maxHealth: 100,
            energy: 100,
            maxEnergy: 100,
            score: 0,
            kills: 0,
            angle: 0,
            boosting: false,
            input: { up: false, down: false, left: false, right: false },
            lastShotTime: 0
        };

        // Notify client of setup
        socket.emit('init_game', {
            id: socket.id,
            worldSize: WORLD_SIZE,
            orbs: orbs
        });

        // Broadcast to chat
        io.emit('chat_message', {
            sender: 'SYSTEM',
            text: `🎮 ${name} присоединился к арене!`,
            color: '#39ff14'
        });
    });

    // Handle inputs
    socket.on('player_input', (input) => {
        const player = players[socket.id];
        if (!player) return;

        player.input = input.movement || player.input;
        player.angle = input.angle !== undefined ? input.angle : player.angle;
        player.boosting = !!input.boosting;
    });

    // Handle shooting
    socket.on('player_shoot', () => {
        const player = players[socket.id];
        if (!player || player.health <= 0) return;

        const now = Date.now();
        if (now - player.lastShotTime < 180) return; // Cooldown 180ms
        player.lastShotTime = now;

        const bId = `b_${socket.id}_${bulletIdCounter++}`;
        const speed = 16;
        const gunOffset = player.radius + 10;

        bullets[bId] = {
            id: bId,
            ownerId: socket.id,
            color: player.color,
            x: player.x + Math.cos(player.angle) * gunOffset,
            y: player.y + Math.sin(player.angle) * gunOffset,
            vx: Math.cos(player.angle) * speed,
            vy: Math.sin(player.angle) * speed,
            damage: 20,
            radius: 5,
            life: 80 // Frames left
        };
    });

    // Chat message
    socket.on('send_chat', (msgText) => {
        const player = players[socket.id];
        if (!player) return;
        const text = String(msgText).trim().substring(0, 80);
        if (!text) return;

        io.emit('chat_message', {
            sender: player.name,
            text: text,
            color: player.color
        });
    });

    // Disconnect
    socket.on('disconnect', () => {
        const player = players[socket.id];
        if (player) {
            io.emit('chat_message', {
                sender: 'SYSTEM',
                text: `🚪 ${player.name} вышел из игры.`,
                color: '#ff007f'
            });
            delete players[socket.id];
        }
        console.log(`Player disconnected: ${socket.id}`);
    });
});

// Server game loop (60 FPS)
setInterval(() => {
    // 1. Update Players
    Object.values(players).forEach(player => {
        if (player.health <= 0) return;

        // Boost logic
        let currentSpeed = player.speed;
        if (player.boosting && player.energy > 5) {
            currentSpeed *= 1.8;
            player.energy = Math.max(0, player.energy - 1.2);
        } else {
            player.energy = Math.min(player.maxEnergy, player.energy + 0.4); // Energy regen
        }

        // Movement calculation
        let dx = 0;
        let dy = 0;
        if (player.input.up) dy -= 1;
        if (player.input.down) dy += 1;
        if (player.input.left) dx -= 1;
        if (player.input.right) dx += 1;

        if (dx !== 0 && dy !== 0) {
            dx *= 0.7071;
            dy *= 0.7071;
        }

        player.x += dx * currentSpeed;
        player.y += dy * currentSpeed;

        // Keep inside map bounds
        player.x = Math.max(player.radius, Math.min(WORLD_SIZE.width - player.radius, player.x));
        player.y = Math.max(player.radius, Math.min(WORLD_SIZE.height - player.radius, player.y));

        // Health slow regen
        if (player.health < player.maxHealth) {
            player.health = Math.min(player.maxHealth, player.health + 0.05);
        }

        // Orb collection collision
        for (let i = orbs.length - 1; i >= 0; i--) {
            const orb = orbs[i];
            const dist = Math.hypot(player.x - orb.x, player.y - orb.y);
            if (dist < player.radius + orb.radius) {
                player.score += orb.scoreValue;
                player.health = Math.min(player.maxHealth, player.health + 2);
                
                // Radius grows slightly with score
                player.radius = Math.min(45, 24 + Math.floor(player.score / 250));

                // Respawn orb
                orbs[i] = spawnOrb();
                io.emit('orb_collected', { orbId: orb.id, newOrb: orbs[i], collectorId: player.id });
            }
        }
    });

    // 2. Update Bullets
    Object.keys(bullets).forEach(bId => {
        const bullet = bullets[bId];
        bullet.x += bullet.vx;
        bullet.y += bullet.vy;
        bullet.life -= 1;

        // Remove expired bullets or out-of-bound bullets
        if (bullet.life <= 0 || bullet.x < 0 || bullet.x > WORLD_SIZE.width || bullet.y < 0 || bullet.y > WORLD_SIZE.height) {
            delete bullets[bId];
            return;
        }

        // Check collision with players
        Object.values(players).forEach(player => {
            if (player.id === bullet.ownerId || player.health <= 0) return;

            const dist = Math.hypot(bullet.x - player.x, bullet.y - player.y);
            if (dist < player.radius + bullet.radius) {
                // Hit!
                player.health -= bullet.damage;
                
                const shooter = players[bullet.ownerId];

                // Notify hit effect
                io.emit('bullet_hit', { x: bullet.x, y: bullet.y, color: bullet.color });
                delete bullets[bId];

                // Check kill
                if (player.health <= 0) {
                    player.health = 0;
                    if (shooter) {
                        shooter.kills += 1;
                        shooter.score += 200;
                    }
                    io.emit('player_died', {
                        victimId: player.id,
                        victimName: player.name,
                        killerName: shooter ? shooter.name : 'Ареной'
                    });

                    io.emit('chat_message', {
                        sender: 'KILL',
                        text: `💥 ${shooter ? shooter.name : 'Арена'} уничтожил ${player.name}!`,
                        color: '#ff007f'
                    });
                }
            }
        });
    });

    // 3. Broadcast snapshot to all clients
    io.emit('game_state', {
        players: players,
        bullets: bullets
    });

}, 1000 / 60);

server.listen(PORT, () => {
    console.log(`🚀 Сервер запущен на http://localhost:${PORT}`);
});
