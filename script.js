// Typing Club Automator - AUTO START (v4 - Game Support)
(function() {
    'use strict';
    if (window.typingClubBot) {
        console.log('Bot already running! Close it first with: window.typingClubBot.close()');
        return;
    }

    console.log('🚀 Loading Typing Club Bot...');

    const gui = document.createElement('div');
    gui.id = 'typing-bot-gui';
    
    // UI Styling: Sleek, Modern, and Rounded
    gui.style.cssText = `
        position: fixed; top: 20px; right: 20px; width: 340px; 
        background: linear-gradient(145deg, #1e202c 0%, #2a2d3e 100%); 
        border: 1px solid rgba(255,255,255,0.1); border-radius: 20px; 
        box-shadow: 0 20px 50px rgba(0,0,0,0.5); z-index: 2147483647; 
        font-family: 'Segoe UI', system-ui, -apple-system, sans-serif; color: white;
        overflow: hidden;
    `;

    gui.innerHTML = `
    <div id="bot-header" style="padding: 15px; background: rgba(255,255,255,0.05); cursor: move; display: flex; justify-content: space-between; align-items: center; font-weight: 700; font-size: 13px; letter-spacing: 0.5px;">
        <span>🎯 EDCLUB BOT: MADE BY Prof_MAN</span>
        <span id="bot-close" style="cursor: pointer; font-size: 22px; line-height: 1; opacity: 0.6;">&times;</span>
    </div>
    
    <div style="padding: 20px;">
        <div style="background: rgba(0,0,0,0.2); padding: 12px; border-radius: 12px; font-size: 11px; margin-bottom: 15px; border: 1px solid rgba(255,255,255,0.05);">
            <strong style="display: block; margin-bottom: 4px; color: #a29bfe; font-size: 10px; text-transform: uppercase;">📍 Detected:</strong>
            <span id="level-info">Waiting...</span>
        </div>
        
        <div style="margin-bottom: 18px;">
            <div style="display: flex; justify-content: space-between; margin-bottom: 8px;">
                <label style="font-size: 11px; font-weight: 600; text-transform: uppercase; opacity: 0.7;">Speed</label>
                <span style="font-size: 14px; font-weight: 700; color: #a29bfe;"><span id="speed-value">70</span> WPM</span>
            </div>
            <input type="range" id="speed-slider" min="30" max="190" value="70" style="width: 100%; cursor: pointer; accent-color: #667eea;">
        </div>
        
        <div style="margin-bottom: 18px;">
            <div style="display: flex; justify-content: space-between; margin-bottom: 8px;">
                <label style="font-size: 11px; font-weight: 600; text-transform: uppercase; opacity: 0.7;">Accuracy</label>
                <span style="font-size: 14px; font-weight: 700; color: #a29bfe;"><span id="accuracy-value">97</span>%</span>
            </div>
            <input type="range" id="accuracy-slider" min="92" max="100" value="97" style="width: 100%; cursor: pointer; accent-color: #667eea;">
        </div>
        
        <div style="display: flex; align-items: center; gap: 10px; background: rgba(255,255,255,0.03); padding: 12px; border-radius: 12px; margin-bottom: 15px;">
            <input type="checkbox" id="auto-advance" checked style="width: 18px; height: 18px; cursor: pointer; accent-color: #667eea;">
            <label for="auto-advance" style="cursor: pointer; flex: 1; font-size: 13px; font-weight: 500;">Auto-advance</label>
        </div>
        
        <button id="start-btn" style="width: 100%; padding: 14px; border: none; border-radius: 12px; font-size: 13px; font-weight: 700; cursor: pointer; text-transform: uppercase; background: #10ac84; color: white; margin-bottom: 10px; transition: 0.2s;">▶ Start Bot</button>
        <button id="stop-btn" disabled style="width: 100%; padding: 14px; border: none; border-radius: 12px; font-size: 13px; font-weight: 700; cursor: pointer; text-transform: uppercase; background: #ff6b6b; color: white; margin-bottom: 15px; opacity: 0.5;">⏹ Stop</button>
        
        <div id="status" style="background: rgba(255,255,255,0.03); padding: 10px; border-radius: 10px; text-align: center; font-size: 12px; font-weight: 600; border: 1px solid rgba(255,255,255,0.05);">Ready</div>
        
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-top: 15px;">
            <div style="background: rgba(0,0,0,0.2); padding: 12px; border-radius: 12px; text-align: center; border: 1px solid rgba(255,255,255,0.05);">
                <div style="font-size: 20px; font-weight: 700; color: #a29bfe;" id="chars-typed">0</div>
                <div style="font-size: 9px; opacity: 0.5; margin-top: 3px; font-weight: 700;">CHARS</div>
            </div>
            <div style="background: rgba(0,0,0,0.2); padding: 12px; border-radius: 12px; text-align: center; border: 1px solid rgba(255,255,255,0.05);">
                <div style="font-size: 20px; font-weight: 700; color: #a29bfe;" id="levels-completed">0</div>
                <div style="font-size: 9px; opacity: 0.5; margin-top: 3px; font-weight: 700;">LEVELS</div>
            </div>
        </div>
    </div>
    `;

    document.body.appendChild(gui);

    const speedSlider = document.getElementById('speed-slider');
    const speedValue = document.getElementById('speed-value');
    const accuracySlider = document.getElementById('accuracy-slider');
    const accuracyValue = document.getElementById('accuracy-value');
    const autoAdvance = document.getElementById('auto-advance');
    const startBtn = document.getElementById('start-btn');
    const stopBtn = document.getElementById('stop-btn');
    const status = document.getElementById('status');
    const levelInfo = document.getElementById('level-info');
    const charsTypedEl = document.getElementById('chars-typed');
    const levelsCompletedEl = document.getElementById('levels-completed');
    const closeBtn = document.getElementById('bot-close');
    const header = document.getElementById('bot-header');

    let botRunning = false;
    let charsTypedCount = 0;
    let levelsCompleted = 0;

    speedSlider.addEventListener('input', (e) => speedValue.textContent = e.target.value);
    accuracySlider.addEventListener('input', (e) => accuracyValue.textContent = e.target.value);

    // Draggable (Logic from v2)
    let isDragging = false;
    let currentX, currentY, initialX, initialY;

    header.addEventListener('mousedown', (e) => {
        initialX = e.clientX - gui.offsetLeft;
        initialY = e.clientY - gui.offsetTop;
        isDragging = true;
    });

    document.addEventListener('mousemove', (e) => {
        if (isDragging) {
            e.preventDefault();
            currentX = e.clientX - initialX;
            currentY = e.clientY - initialY;
            gui.style.left = currentX + 'px';
            gui.style.top = currentY + 'px';
            gui.style.right = 'auto';
        }
    });

    document.addEventListener('mouseup', () => isDragging = false);

    function detectLevel() {
        // --- UPDATED: handle span.token_unit (chars + spaces) and span._enter ---
        const letters = document.querySelectorAll('div.typable span.token_unit');
        if (letters && letters.length > 0) {
            const text = Array.from(letters).map(s => {
                if (s.querySelector('._enter') || s.querySelector('br')) return '\n'; // Enter token (._enter is nested inside token_unit)
                if (s.querySelector('i')) return ' ';                                 // Space token (has <i> child)
                return s.textContent;                                                 // Regular character token
            }).join('');
            levelInfo.textContent = `${text.length} chars detected`;
            return { text, type: 'typing' };
        }
        // --- END UPDATED ---

        const typable = document.querySelector('div.typable');
        if (typable && typable.textContent) {
            const text = typable.textContent.trim().replace(/\s+/g, ' ');
            levelInfo.textContent = `${text.length} chars detected`;
            return { text, type: 'typing' };
        }

        // --- UPDATED: identify TypingClub typing games specifically via approuter ---
        try {
            const app = window.approuter?.lesson?.activity?.app;
            if (app && app.startsWith('typing.games.')) {
                const gameName = app.split('.')[2]; // e.g. "FloatingBubbles", "BalloonValley"
                levelInfo.textContent = `Game: ${gameName}`;
                return { text: null, type: 'game', gameName };
            }
        } catch (e) {}

        const gameContainer = document.querySelector('#game canvas, #game');
        if (gameContainer) {
            levelInfo.textContent = 'Game detected';
            return { text: null, type: 'game', gameName: 'unknown' };
        }
        // --- END UPDATED ---

        return { text: null, type: null };
    }

    function typeChar(char, field) {
        const keyCode = char.charCodeAt(0);
        let code = 'Unidentified';
        let shiftKey = false;

        const specialChars = {
            ' ': { code: 'Space', keyCode: 32 },
            '\n': { code: 'Enter', keyCode: 13 },
            '"': { code: 'Quote', keyCode: 222, shiftKey: true },
            "'": { code: 'Quote', keyCode: 222, shiftKey: false },
            ',': { code: 'Comma', keyCode: 188 },
            '.': { code: 'Period', keyCode: 190 },
            '!': { code: 'Digit1', keyCode: 49, shiftKey: true },
            '?': { code: 'Slash', keyCode: 191, shiftKey: true },
            ':': { code: 'Semicolon', keyCode: 186, shiftKey: true },
            ';': { code: 'Semicolon', keyCode: 186 },
            '-': { code: 'Minus', keyCode: 189 },
            '(': { code: 'Digit9', keyCode: 57, shiftKey: true },
            ')': { code: 'Digit0', keyCode: 48, shiftKey: true }
        };

        if (specialChars[char]) {
            code = specialChars[char].code;
            shiftKey = specialChars[char].shiftKey || false;
        } else if (/[a-z]/.test(char)) {
            code = `Key${char.toUpperCase()}`;
            shiftKey = false;
        } else if (/[A-Z]/.test(char)) {
            code = `Key${char}`;
            shiftKey = true;
        } else if (/[0-9]/.test(char)) {
            code = `Digit${char}`;
            shiftKey = false;
        }

        const isEnter = (char === '\n' || char === '\r');
        const opts = {
            key: isEnter ? 'Enter' : char, code: code, keyCode: isEnter ? 13 : keyCode, which: isEnter ? 13 : keyCode,
            shiftKey: shiftKey, bubbles: true, cancelable: true, composed: true, view: window
        };
        field.dispatchEvent(new KeyboardEvent('keydown', opts));
        field.dispatchEvent(new KeyboardEvent('keypress', opts));
        if (!isEnter) {
            field.value += char;
            field.dispatchEvent(new Event('input', { bubbles: true }));
            field.dispatchEvent(new Event('change', { bubbles: true }));
        }
        field.dispatchEvent(new KeyboardEvent('keyup', opts));
    }

    // --- PATCHED: Type a single word into the game ---
    //
    // Complete TypingCore input chain (typing_core.js, confirmed):
    //
    //   TypingCore.init_keyboard_focus() creates a hidden <input> and prepends
    //   it to <body>.  attach_capture() binds three jQuery handlers TO THAT INPUT:
    //
    //     $focusInput.keydown  → _input_handler_keydown → this.keyDown = e.keyCode
    //     $focusInput.input    → _input_handler          → key = $focusInput.val()
    //                                                       record_keydown_time(key)
    //                                                       $focusInput.val('')   ← clears
    //     $focusInput.keyup    → _input_handler_keyup    → this.prev_key = null
    //
    //   record_keydown_time is monkey-patched by GameWordManager, which buffers
    //   chars, matches them against active word char_lists, and fires
    //   core.events("keydown", {is_valid, chr}) that the Phaser game listens to.
    //
    //   Fallback (iOS / no_input_mode):
    //     $(document).keypress → _keypress_handler → record_keydown_time(e.key)
    //
    //   Bonus: TypingCore.idkfa() calls record_keydown_time() directly for each
    //   char. If the core is reachable we call that instead of synthesising events.
    //
    async function typeWordToGame(word) {
        const wpm       = parseInt(speedSlider.value);
        const baseDelay = 60000 / (wpm * 5);

        // ── Path A: idkfa() — calls record_keydown_time directly on the core ────
        // GameWordManager replaces core.record_keydown_time, so this goes through
        // the full word-matching pipeline without any DOM event synthesis.
        // The core is at this.core inside the Phaser MainState. In DEV_MODE
        // games expose window.game; otherwise we can still find the core via the
        // hidden input's jQuery data that TypingCore stores on the element.
        const tryIdkfa = () => {
            try {
                // DEV_MODE path
                const g = window.game;
                if (g?.state) {
                    const st = g.state.states[g.state.current];
                    if (typeof st?.core?.record_keydown_time === 'function') {
                        for (const char of word) {
                            st.core.record_keydown_time(char);
                        }
                        return true;
                    }
                }
            } catch (_) {}
            return false;
        };

        if (tryIdkfa()) {
            charsTypedCount += word.length;
            charsTypedEl.textContent = charsTypedCount;
            return true;
        }

        // ── Path B: hidden $focus_input events (desktop / normal mode) ──────────
        // Selector: body > input[type='text'][aria-hidden='true']
        // TypingCore does: $('body').prepend($inpt) with aria-hidden=true
        const focusInput = document.querySelector(
            "body > input[type='text'][aria-hidden='true']"
        );

        if (focusInput) {
            focusInput.focus();

            for (const char of word) {
                if (!botRunning) return false;

                const upper   = char.toUpperCase();
                // Physical key code: always uppercase ASCII for letters
                const keyCode = /[a-zA-Z]/.test(char) ? upper.charCodeAt(0) : char.charCodeAt(0);
                const keyOpts = {
                    key:        char,
                    code:       /[a-zA-Z]/.test(char) ? `Key${upper}` : 'Unidentified',
                    keyCode,
                    which:      keyCode,
                    bubbles:    true,
                    cancelable: true,
                    composed:   true,
                    view:       window,
                };

                // 1. keydown → _input_handler_keydown sets this.keyDown = e.keyCode
                focusInput.dispatchEvent(new KeyboardEvent('keydown', keyOpts));

                // 2. Set value then fire input → _input_handler reads val, calls
                //    record_keydown_time(key), then clears the input itself
                focusInput.value = char;
                focusInput.dispatchEvent(new Event('input', { bubbles: true }));

                // 3. keyup → _input_handler_keyup resets this.prev_key = null
                //    (required so canUseKeyUpEvent guard allows the next char)
                focusInput.dispatchEvent(new KeyboardEvent('keyup', keyOpts));

                charsTypedCount++;
                charsTypedEl.textContent = charsTypedCount;
                await new Promise(r => setTimeout(r, baseDelay * (0.8 + Math.random() * 0.4)));
            }
            return true;
        }

        // ── Path C: $(document).keypress fallback (iOS / no_input_mode) ─────────
        // _keypress_handler reads e.key and calls record_keydown_time directly.
        console.warn('⚠️ focusInput not found — falling back to document keypress');
        for (const char of word) {
            if (!botRunning) return false;
            const keyCode = char.charCodeAt(0);
            document.dispatchEvent(new KeyboardEvent('keypress', {
                key:        char,
                keyCode,
                which:      keyCode,
                charCode:   keyCode,
                bubbles:    true,
                cancelable: true,
                composed:   true,
                view:       window,
            }));
            charsTypedCount++;
            charsTypedEl.textContent = charsTypedCount;
            await new Promise(r => setTimeout(r, baseDelay * (0.8 + Math.random() * 0.4)));
        }
        return true;
    }


    // ─────────────────────────────────────────────────────────────────────────
    // PATCHED: Main game handler
    //
    // Detection strategy — two-tier:
    //
    //   Tier 1 (opportunistic): CanvasRenderingContext2D.fillText intercept.
    //   Works when the game uses Phaser.Text, which renders each word to a
    //   private off-screen 2D canvas.  Installed immediately so it covers all
    //   future renders without needing the Phaser instance.
    //
    //   Tier 2 (primary fallback): direct lesson-text typing.
    //   TypingClub games draw words via Phaser.BitmapText (glyph sprites —
    //   confirmed present in phaser_1237_min.js), which never calls fillText.
    //   When the hook captures nothing after a 3-second probe window, the bot
    //   reads words directly from approuter.lesson and types them in order.
    //   The game accepts each word that matches a live target and ignores the
    //   rest, so the bot makes progress without needing live canvas state.
    // ─────────────────────────────────────────────────────────────────────────
    async function processTypingGame(gameName) {
        console.log(`🎮 Typing game detected: ${gameName}`);
        status.textContent = `🎮 ${gameName}…`;

        // ── 1. Load lesson words (used for fillText filter AND direct fallback) ──
        //
        // The source shows `a.details.lesson_text` where `a` has both
        // `a.lesson` and `a.details` as sibling keys — meaning lesson text
        // lives at approuter.details.lesson_text, NOT inside approuter.lesson.
        // We try every plausible path, then fall back to a recursive scan of
        // the entire approuter object tree so future API changes don't break us.
        let lessonWords = [];
        try {
            // Explicit paths — ordered most-to-least likely.
            // Confirmed in games_1237_min.js: game core is initialised with
            //   text: t.activity.text   where t = approuter.lesson
            // Some games strip spaces: .replace(/\s/g,"") — we keep them for
            // word splitting, then remove spaces when building the queue below.
            const PATHS = [
                () => window.approuter?.lesson?.activity?.text,
                () => window.approuter?.details?.lesson_text,
                () => window.approuter?.lesson?.activity?.lesson_text,
                () => window.approuter?.lesson?.details?.lesson_text,
                () => window.approuter?.lesson?.text,
                () => window.approuter?.lesson?.lesson_text,
            ];

            let raw = null;
            for (const fn of PATHS) {
                try { raw = fn(); } catch (_) {}
                if (typeof raw === 'string' && raw.trim().length > 1) break;
                raw = null;
            }

            // Deep-scan fallback: walk approuter up to 4 levels looking for
            // any property literally named 'lesson_text'
            if (!raw) {
                const seen = new WeakSet();
                const deepFind = (obj, depth) => {
                    if (depth > 4 || !obj || typeof obj !== 'object' || seen.has(obj)) return null;
                    seen.add(obj);
                    if (typeof obj.lesson_text === 'string' && obj.lesson_text.trim()) return obj.lesson_text.trim();
                    for (const k of Object.keys(obj)) {
                        try { const r = deepFind(obj[k], depth + 1); if (r) return r; } catch (_) {}
                    }
                    return null;
                };
                try { raw = deepFind(window.approuter, 0); } catch (_) {}
            }

            if (typeof raw === 'string' && raw.trim()) {
                lessonWords = raw.trim().split(/\s+/).filter(Boolean);
                console.log(`📋 ${lessonWords.length} lesson words loaded`);
            } else {
                // Emit a diagnostic dump so the correct path can be found manually
                console.warn('⚠️ lesson_text not found. approuter snapshot:',
                    JSON.stringify({
                        keys:          Object.keys(window.approuter || {}),
                        detailsKeys:   Object.keys(window.approuter?.details || {}),
                        lessonKeys:    Object.keys(window.approuter?.lesson || {}),
                        activityKeys:  Object.keys(window.approuter?.lesson?.activity || {}),
                    }, null, 2));
            }
        } catch (_) {}
        const lessonSet = new Set(lessonWords.map(w => w.toLowerCase()));

        // ── 2. Tier-1: fillText prototype intercept ───────────────────────────────
        // Phaser.Text calls this.context.fillText() on a private off-screen canvas
        // every time its text property is updated.  Patching the prototype here
        // catches all 2D contexts — including ones already created — because
        // prototype lookup happens at call time, not at object creation time.
        const wordQueue  = [];
        const recentSeen = new Map();
        const DEDUP_MS   = 250;    // collapse shadow + fill passes of the same word
        const WORD_RE    = /^[a-zA-Z']{1,30}$/;

        const origFillText = CanvasRenderingContext2D.prototype.fillText;
        CanvasRenderingContext2D.prototype.fillText = function (text, x, y, ...rest) {
            const word = String(text ?? '').trim();
            if (WORD_RE.test(word)) {
                const lw  = word.toLowerCase();
                const now = Date.now();
                const ok  = (lessonSet.size === 0 || lessonSet.has(lw))
                         && (!recentSeen.has(lw) || now - recentSeen.get(lw) > DEDUP_MS);
                if (ok) {
                    recentSeen.set(lw, now);
                    wordQueue.push(word);
                    console.log(`📥 fillText: "${word}" (q=${wordQueue.length})`);
                }
            }
            return origFillText.call(this, text, x, y, ...rest);
        };
        const unhook = () => { CanvasRenderingContext2D.prototype.fillText = origFillText; };

        // ── 3. DOM-only game-done check ───────────────────────────────────────────
        const isGameDone = () => {
            const el = document.querySelector('#game');
            return !el || el.style.display === 'none'
                || !!window.approuter?.modelManager?._attempt;
        };

        // ── 4. Wait for the game canvas ───────────────────────────────────────────
        status.textContent = `🎮 ${gameName} — waiting for canvas…`;
        let canvas = null;
        for (let i = 0; i < 80 && !canvas; i++) {
            canvas = document.querySelector('#game canvas');
            if (!canvas) await new Promise(r => setTimeout(r, 100));
        }
        if (!canvas) {
            unhook();
            status.textContent = '⚠️ Game canvas not found';
            console.error('❌ #game canvas never appeared');
            stopBot();
            return;
        }

        // Allow the game's preload → create cycle to finish so first words render
        await new Promise(r => setTimeout(r, 800));
        status.textContent = `🎮 ${gameName} — detecting words…`;
        console.log('✅ Canvas ready — probing fillText hook for 3 s…');

        // ── 5. 3-second probe: give fillText hook a chance to capture words ───────
        const probeEnd = Date.now() + 3000;
        while (botRunning && !isGameDone() && wordQueue.length === 0 && Date.now() < probeEnd) {
            await new Promise(r => setTimeout(r, 150));
        }

        // ── 6. Tier-2 fallback if fillText captured nothing ───────────────────────
        if (wordQueue.length === 0) {
            if (lessonWords.length === 0) {
                unhook();
                status.textContent = '⚠️ No words — cannot read approuter.lesson';
                console.error('❌ lessonWords empty and fillText yielded nothing');
                stopBot();
                return;
            }
            // Game uses BitmapText (or hook missed the window).
            // Seed the queue with lesson words in their native order.
            // The game accepts each word that matches a live target and ignores others.
            console.log(`ℹ️ fillText inactive — direct lesson-word mode (${lessonWords.length} words)`);
            status.textContent = `📝 Direct mode: ${lessonWords.length} words`;
            for (const w of lessonWords) wordQueue.push(w); // no trailing space — GameWordManager matches exact chars
        }

        // ── 7. Main typing loop ───────────────────────────────────────────────────
        // In direct mode the game keeps spawning monsters/bubbles throughout its
        // full duration, so we cycle the word list continuously rather than
        // stopping after one pass.  fillText mode drains naturally as the game
        // queues new words itself.
        const isDirectMode = wordQueue.length > 0 && lessonWords.length > 0
                          && wordQueue[0] === lessonWords[0];  // seeded from lesson list
        let staleTicks = 0;
        const TICK_MS   = 100;
        const MAX_STALE = 300;   // 300 × 100 ms ≈ 30 s

        while (botRunning) {
            if (isGameDone()) break;

            if (wordQueue.length > 0) {
                staleTicks = 0;
                const word = wordQueue.shift();
                status.textContent = `⌨️ "${word}"`;
                console.log(`⌨️ Typing: "${word}"`);
                await typeWordToGame(word);
                // Brief gap so the game registers the completed word before the next arrives
                await new Promise(r => setTimeout(r, 180 + Math.random() * 120));
            } else if (isDirectMode && lessonWords.length > 0) {
                // Queue exhausted in direct mode — reload and keep going
                staleTicks = 0;
                console.log('🔄 Reloading word list for next wave…');
                for (const w of lessonWords) wordQueue.push(w); // reload for next wave
            } else {
                staleTicks++;
                if (staleTicks >= MAX_STALE) {
                    console.warn('⏳ Queue empty for ~30 s — assuming game complete');
                    break;
                }
                await new Promise(r => setTimeout(r, TICK_MS));
            }
        }

        // ── 8. Level complete ─────────────────────────────────────────────────────
        unhook();
        console.log(`✅ Game complete: ${gameName}`);
        levelsCompleted++;
        levelsCompletedEl.textContent = levelsCompleted;
        status.textContent = '✅ Game complete!';

        if (autoAdvance.checked) {
            await new Promise(r => setTimeout(r, 4000));
            const enterOpts = {
                key: 'Enter', code: 'Enter', keyCode: 13, which: 13,
                bubbles: true, cancelable: true, view: window
            };
            document.dispatchEvent(new KeyboardEvent('keydown', enterOpts));
            document.dispatchEvent(new KeyboardEvent('keyup', enterOpts));
            document.body.click();
            document.querySelectorAll('button, .btn, [role="button"], div[onclick], a')
                    .forEach(el => {
                        if (el.offsetParent !== null && !el.closest('#typing-bot-gui')) el.click();
                    });
            await new Promise(r => setTimeout(r, 1000));
            if (botRunning) processLevel();
        } else {
            stopBot();
        }
    }
    // ─────────────────────────────────────────────────────────────────────────
    // END PATCH
    // ─────────────────────────────────────────────────────────────────────────


    async function processLevel() {
        if (!botRunning) return;

        const level = detectLevel();

        if (!level.text && level.type !== 'game') {
            status.textContent = '⚠️ No text or game found';
            console.log('❌ Could not find text or game');
            stopBot();
            return;
        }

        // --- UPDATED: delegate all game handling to processTypingGame() ---
        if (level.type === 'game') {
            await processTypingGame(level.gameName || 'unknown');
            return;
        }
        // --- END UPDATED ---

        const text = level.text;
        console.log('📝 Text:', text);
        status.textContent = '👆 Starting lesson...';

        const typingArea = document.querySelector('.tpmodes, .typable, .inview');
        if (typingArea) { typingArea.click(); }
        document.body.click();
        document.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', keyCode: 32, bubbles: true }));
        await new Promise(r => setTimeout(r, 500));

        let input = null;
        for (let attempt = 0; attempt < 30; attempt++) {
            const allInputs = document.querySelectorAll('input[type="text"]');
            for (const inp of allInputs) { if (inp.type === 'text') { input = inp; break; } }
            if (input) break;
            await new Promise(r => setTimeout(r, 100));
        }

        if (!input) {
            status.textContent = '⚠️ Input not found';
            console.log('❌ No input field found at all');
            stopBot();
            return;
        }

        console.log('🚀 Typing... did you know that Prof_MAN modified this!!!!!!!!!');
        input.value = '';
        input.focus();
        await new Promise(r => setTimeout(r, 100));

        const wpm = parseInt(speedSlider.value);
        const accuracy = parseInt(accuracySlider.value);
        const baseDelay = 60000 / (wpm * 5);
        status.textContent = `⌨️ Typing...`;

        let burstMultiplier = 1.0;
        let burstCharsLeft = 0;

        for (let i = 0; i < text.length; i++) {
            if (!botRunning) return;
            if (burstCharsLeft <= 0) {
                const roll = Math.random();
                if (roll < 0.35) { burstMultiplier = 0.5 + Math.random() * 0.3; } 
                else if (roll < 0.65) { burstMultiplier = 0.9 + Math.random() * 0.2; } 
                else { burstMultiplier = 1.2 + Math.random() * 0.7; }
                burstCharsLeft = 3 + Math.floor(Math.random() * 8);
            }
            burstCharsLeft--;

            const char = text[i];
            const shouldError = Math.random() * 100 > accuracy;
            
            if (shouldError && /[a-z]/i.test(char)) {
                const wrong = String.fromCharCode(char.charCodeAt(0) + (Math.random() > 0.5 ? 1 : -1));
                typeChar(wrong, input);
                await new Promise(r => setTimeout(r, baseDelay * 0.5));
                const backspaceOpts = { key: 'Backspace', code: 'Backspace', keyCode: 8, which: 8, bubbles: true, cancelable: true, view: window };
                input.dispatchEvent(new KeyboardEvent('keydown', backspaceOpts));
                input.dispatchEvent(new KeyboardEvent('keypress', backspaceOpts));
                input.value = input.value.slice(0, -1);
                input.dispatchEvent(new Event('input', { bubbles: true }));
                input.dispatchEvent(new Event('change', { bubbles: true }));
                input.dispatchEvent(new KeyboardEvent('keyup', backspaceOpts));
                await new Promise(r => setTimeout(r, 300));
            }
            
            typeChar(char, input);
            charsTypedCount++;
            charsTypedEl.textContent = charsTypedCount;
            
            let delay = baseDelay * burstMultiplier * (0.8 + Math.random() * 0.4);
            if (['.', '!', '?'].includes(char)) delay *= 2;
            else if (char === ' ') delay *= 1.3;
            await new Promise(r => setTimeout(r, delay));
        }

        console.log('✅ Complete! 67');
        levelsCompleted++;
        levelsCompletedEl.textContent = levelsCompleted;
        status.textContent = '✅ Complete! Waiting...';

        if (autoAdvance.checked) {
            await new Promise(r => setTimeout(r, 6000));
            const enterOpts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true, view: window };
            document.dispatchEvent(new KeyboardEvent('keydown', enterOpts));
            document.dispatchEvent(new KeyboardEvent('keypress', enterOpts));
            document.dispatchEvent(new KeyboardEvent('keyup', enterOpts));
            if (input) {
                input.dispatchEvent(new KeyboardEvent('keydown', enterOpts));
                input.dispatchEvent(new KeyboardEvent('keypress', enterOpts));
                input.dispatchEvent(new KeyboardEvent('keyup', enterOpts));
            }
            document.body.dispatchEvent(new KeyboardEvent('keydown', enterOpts));
            document.body.dispatchEvent(new KeyboardEvent('keypress', enterOpts));
            document.body.dispatchEvent(new KeyboardEvent('keyup', enterOpts));
            document.body.click();
            const centerX = window.innerWidth / 2;
            const centerY = window.innerHeight / 2;
            const centerEl = document.elementFromPoint(centerX, centerY);
            if (centerEl && !centerEl.closest('#typing-bot-gui')) { centerEl.click(); }
            const clickables = document.querySelectorAll('button, .btn, [role="button"], div[onclick], a');
            clickables.forEach(el => { if (el.offsetParent !== null && !el.closest('#typing-bot-gui')) { el.click(); } });
            await new Promise(r => setTimeout(r, 1000));
            if (botRunning) processLevel();
        } else { stopBot(); }
    }

    function startBot() {
        botRunning = true;
        startBtn.disabled = true;
        stopBtn.disabled = false;
        stopBtn.style.opacity = '1';
        console.log('🤖 Bot started');
        processLevel();
    }

    function stopBot() {
        botRunning = false;
        startBtn.disabled = false;
        stopBtn.disabled = true;
        stopBtn.style.opacity = '0.5';
        status.textContent = '⏹ Stopped';
    }

    function closeBot() {
        stopBot();
        gui.remove();
        window.typingClubBot = null;
    }

    startBtn.addEventListener('click', startBot);
    stopBtn.addEventListener('click', stopBot);
    closeBtn.addEventListener('click', closeBot);

    window.typingClubBot = { start: startBot, stop: stopBot, close: closeBot };

    setTimeout(detectLevel, 500);
    console.log('✅ Bot loaded! Just click Start Bot.(67)');
})();
