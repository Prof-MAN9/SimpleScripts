// Script - AUTO START (v4 - Bug Fixes; advanced logic)
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
                <span style="font-size: 14px; font-weight: 700; color: #a29bfe;"><span id="speed-value">50</span> WPM</span>
            </div>
            <input type="range" id="speed-slider" min="20" max="190" value="50" style="width: 100%; cursor: pointer; accent-color: #667eea;">
        </div>
        
        <div style="margin-bottom: 18px;">
            <div style="display: flex; justify-content: space-between; margin-bottom: 8px;">
                <label style="font-size: 11px; font-weight: 600; text-transform: uppercase; opacity: 0.7;">Accuracy</label>
                <span style="font-size: 14px; font-weight: 700; color: #a29bfe;"><span id="accuracy-value">94</span>%</span>
            </div>
            <input type="range" id="accuracy-slider" min="80" max="100" value="94" style="width: 100%; cursor: pointer; accent-color: #667eea;">
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
        // Boxed typing activity — characters live in .boxed-char divs inside
        // .boxed-line rows.  &nbsp; entries are spaces; collect all in order.
        const boxedChars = document.querySelectorAll('.boxed-line .boxed-char');
        if (boxedChars.length > 0) {
            const text = Array.from(boxedChars).map(el => {
                const t = el.textContent;
                // &nbsp; renders as   — treat as a regular space
                return t === ' ' || t === ' ' ? ' ' : t;
            }).join('');
            levelInfo.textContent = `Boxed: ${text.length} chars`;
            return { text, type: 'typing' };
        }

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

        // Instruction / intro screen — appears between lessons and after games.
        // Identified by the presence of a visible .navbar-continue ("Next") button
        // or the #instruction container.  Press Enter to advance.
        const continueBtn = document.querySelector('.navbar-continue');
        if (continueBtn && continueBtn.offsetParent !== null) {
            levelInfo.textContent = 'Instruction screen';
            return { text: null, type: 'instruction' };
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
    // Games and activities use a lower WPM (≈ slider×0.65) and higher error
    // rate (slider accuracy − 6pp, floored at 80%) to look more natural under
    // the pressure/distraction of a game environment.
    //
    // Key-adjacency map is defined in the normal typing loop; duplicated here
    // so typeWordToGame is self-contained.
    //
    async function typeWordToGame(word) {
        const GAME_KEY_NEIGHBORS = {
            q:['w','a','s'],      w:['q','e','a','s','d'],   e:['w','r','s','d','f'],
            r:['e','t','d','f','g'], t:['r','y','f','g','h'], y:['t','u','g','h','j'],
            u:['y','i','h','j','k'], i:['u','o','j','k','l'], o:['i','p','k','l'],
            p:['o','l'],
            a:['q','w','s','z'],  s:['a','d','w','e','x','z'], d:['s','f','e','r','x','c'],
            f:['d','g','r','t','c','v'], g:['f','h','t','y','v','b'], h:['g','j','y','u','b','n'],
            j:['h','k','u','i','n','m'], k:['j','l','i','o','m'],     l:['k','p','o'],
            z:['a','s','x'],      x:['z','c','s','d'],        c:['x','v','d','f'],
            v:['c','b','f','g'],  b:['v','n','g','h'],        n:['b','m','h','j'],
            m:['n','j','k'],
        };
        function gameAdjacentTypo(ch) {
            const key = ch.toLowerCase();
            const nb = GAME_KEY_NEIGHBORS[key];
            if (!nb || !nb.length) return null;
            const p = nb[Math.floor(Math.random() * nb.length)];
            return ch === ch.toUpperCase() ? p.toUpperCase() : p;
        }

        // Game WPM is 65% of the slider value, minimum 20
        const wpm       = Math.max(20, Math.round(parseInt(speedSlider.value) * 0.65));
        // Game error rate is 6pp higher than slider accuracy, minimum 80%
        const accuracy  = Math.max(80, parseInt(accuracySlider.value) - 6);
        const errorChance = (100 - accuracy) / 100;
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
                const keyCode = /[a-zA-Z]/.test(char) ? upper.charCodeAt(0) : char.charCodeAt(0);

                // ── Adjacent-key error injection ──────────────────────────────
                if (/[a-zA-Z]/.test(char) && Math.random() < errorChance) {
                    const typo = gameAdjacentTypo(char);
                    if (typo) {
                        const typoCode = typo.toUpperCase().charCodeAt(0);
                        const typoOpts = { key: typo, code: `Key${typo.toUpperCase()}`,
                            keyCode: typoCode, which: typoCode, bubbles: true,
                            cancelable: true, composed: true, view: window };
                        focusInput.dispatchEvent(new KeyboardEvent('keydown', typoOpts));
                        focusInput.value = typo;
                        focusInput.dispatchEvent(new Event('input', { bubbles: true }));
                        focusInput.dispatchEvent(new KeyboardEvent('keyup', typoOpts));
                        charsTypedCount++;
                        charsTypedEl.textContent = charsTypedCount;
                        await new Promise(r => setTimeout(r, baseDelay * (0.5 + Math.random() * 0.3)));
                        // Correct immediately with Backspace
                        const bsOpts = { key:'Backspace', code:'Backspace', keyCode:8, which:8,
                                         bubbles:true, cancelable:true, view:window };
                        focusInput.dispatchEvent(new KeyboardEvent('keydown', bsOpts));
                        focusInput.value = '';
                        focusInput.dispatchEvent(new Event('input',  { bubbles:true }));
                        focusInput.dispatchEvent(new KeyboardEvent('keyup', bsOpts));
                        await new Promise(r => setTimeout(r, 100 + Math.random() * 120));
                    }
                }

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
                await new Promise(r => setTimeout(r, baseDelay * (0.75 + Math.random() * 0.5)));
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
            await new Promise(r => setTimeout(r, baseDelay * (0.75 + Math.random() * 0.5)));
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

        if (!level.text && level.type !== 'game' && level.type !== 'instruction') {
            status.textContent = '⚠️ No text or game found';
            console.log('❌ Could not find text or game');
            stopBot();
            return;
        }

        // Instruction / intro screen — click the continue button and press Enter
        if (level.type === 'instruction') {
            status.textContent = '⏭ Skipping instruction…';
            console.log('📖 Instruction screen detected — pressing Enter');
            await new Promise(r => setTimeout(r, 800));
            const enterOpts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13,
                                bubbles: true, cancelable: true, view: window };
            // Click the button directly (most reliable)
            const btn = document.querySelector('.navbar-continue');
            if (btn) btn.click();
            // Also dispatch Enter in case the button isn't focused
            document.dispatchEvent(new KeyboardEvent('keydown', enterOpts));
            document.dispatchEvent(new KeyboardEvent('keyup',   enterOpts));
            await new Promise(r => setTimeout(r, 1500));
            if (botRunning) processLevel();
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

        // ── Human-typing model ────────────────────────────────────────────────
        //
        // Key-adjacency map for realistic typo selection.
        // Each entry lists the physically neighbouring keys on a QWERTY layout.
        const KEY_NEIGHBORS = {
            q:['w','a','s'],      w:['q','e','a','s','d'],   e:['w','r','s','d','f'],
            r:['e','t','d','f','g'], t:['r','y','f','g','h'], y:['t','u','g','h','j'],
            u:['y','i','h','j','k'], i:['u','o','j','k','l'], o:['i','p','k','l'],
            p:['o','l'],
            a:['q','w','s','z'],  s:['a','d','w','e','x','z'], d:['s','f','e','r','x','c'],
            f:['d','g','r','t','c','v'], g:['f','h','t','y','v','b'], h:['g','j','y','u','b','n'],
            j:['h','k','u','i','n','m'], k:['j','l','i','o','m'],     l:['k','p','o'],
            z:['a','s','x'],      x:['z','c','s','d'],        c:['x','v','d','f'],
            v:['c','b','f','g'],  b:['v','n','g','h'],        n:['b','m','h','j'],
            m:['n','j','k'],
            '1':['2','q'],  '2':['1','3','w'],  '3':['2','4','e'],  '4':['3','5','r'],
            '5':['4','6','t'],  '6':['5','7','y'],  '7':['6','8','u'],  '8':['7','9','i'],
            '9':['8','0','o'],  '0':['9','p'],
        };

        // Home-row distance cost (extra ms per step away from home row).
        // Home row = a-l  (cost 0).  Top row = q-p  (cost 1).
        // Bottom row = z-m (cost 1).  Number row (cost 2).
        function homeRowCost(ch) {
            const c = ch.toLowerCase();
            if ('asdfghjkl'.includes(c))   return 0;
            if ('qwertyuiop'.includes(c))  return 1;
            if ('zxcvbnm'.includes(c))     return 1;
            if ('1234567890'.includes(c))  return 2;
            return 0.5;
        }

        // Pick a realistic adjacent-key typo for a character.
        function adjacentTypo(ch) {
            const key = ch.toLowerCase();
            const neighbors = KEY_NEIGHBORS[key];
            if (!neighbors || neighbors.length === 0) return null;
            const pick = neighbors[Math.floor(Math.random() * neighbors.length)];
            // Preserve original case
            return ch === ch.toUpperCase() ? pick.toUpperCase() : pick;
        }

        const targetWpm  = parseInt(speedSlider.value);
        const accuracy   = parseInt(accuracySlider.value);

        // Actual WPM floats around target with ±8 WPM std-dev (re-sampled per char cluster).
        let sessionWpm   = targetWpm;
        let sessionResampleIn = 0;

        // Fatigue: speed decreases ~4% per minute of typing.
        const sessionStartTime = Date.now();

        // Post-error caution: slow down for N chars after a mistake.
        let cautionCharsLeft  = 0;

        // Warm-up: first 12 chars are slower.
        let warmupCharsLeft   = 12;

        // Pending delayed-detection backspace:
        // sometimes the bot "notices" a mistake 1-3 chars late.
        let pendingBackspaceAt = -1;  // char index at which to correct

        status.textContent = `⌨️ Typing...`;

        // Start delay — simulate the user reading the first word.
        await new Promise(r => setTimeout(r, 250 + Math.random() * 400));

        for (let i = 0; i < text.length; i++) {
            if (!botRunning) return;

            // ── Resample session WPM every 15-25 chars ──────────────────────
            if (sessionResampleIn <= 0) {
                const drift = (Math.random() - 0.5) * 16;   // ±8 WPM
                sessionWpm = Math.max(20, targetWpm + drift);
                sessionResampleIn = 15 + Math.floor(Math.random() * 10);
            }
            sessionResampleIn--;

            // ── Fatigue: -4% per minute ──────────────────────────────────────
            const elapsedMin = (Date.now() - sessionStartTime) / 60000;
            const fatigueMultiplier = 1 + elapsedMin * 0.04;

            // ── Base delay from current effective WPM ────────────────────────
            const effectiveWpm = sessionWpm / fatigueMultiplier;
            let baseDelay = 60000 / (effectiveWpm * 5);

            // ── Warm-up: first 12 chars 35% slower ──────────────────────────
            if (warmupCharsLeft > 0) {
                baseDelay *= 1.35;
                warmupCharsLeft--;
            }

            // ── Post-error caution: 25% slower ──────────────────────────────
            if (cautionCharsLeft > 0) {
                baseDelay *= 1.25;
                cautionCharsLeft--;
            }

            // ── Finger travel time (home-row distance) ───────────────────────
            const char = text[i];
            baseDelay += homeRowCost(char) * 18;

            // ── Burst multiplier (sprint/pause rhythm) ───────────────────────
            const burstRoll = Math.random();
            let burstMult;
            if      (burstRoll < 0.30) burstMult = 0.55 + Math.random() * 0.25;  // sprint
            else if (burstRoll < 0.65) burstMult = 0.90 + Math.random() * 0.20;  // normal
            else                       burstMult = 1.20 + Math.random() * 0.60;  // slow

            // ── Thinking pause: 3% chance of a 300-700ms gap ────────────────
            if (Math.random() < 0.03) {
                await new Promise(r => setTimeout(r, 300 + Math.random() * 400));
            }

            // ── Delayed-detection correction ─────────────────────────────────
            if (i === pendingBackspaceAt) {
                pendingBackspaceAt = -1;
                const stepsBack = 1 + Math.floor(Math.random() * 2);
                for (let b = 0; b < stepsBack; b++) {
                    const bsOpts = { key:'Backspace', code:'Backspace', keyCode:8, which:8,
                                     bubbles:true, cancelable:true, view:window };
                    input.dispatchEvent(new KeyboardEvent('keydown',  bsOpts));
                    input.dispatchEvent(new KeyboardEvent('keypress', bsOpts));
                    input.value = input.value.slice(0, -1);
                    input.dispatchEvent(new Event('input',  { bubbles:true }));
                    input.dispatchEvent(new Event('change', { bubbles:true }));
                    input.dispatchEvent(new KeyboardEvent('keyup', bsOpts));
                    await new Promise(r => setTimeout(r, baseDelay * 0.9));
                }
                // Re-type the chars we deleted (simplified: retype current char only)
                await new Promise(r => setTimeout(r, 150 + Math.random() * 100));
            }

            // ── Error injection ──────────────────────────────────────────────
            const errorChance = (100 - accuracy) / 100;
            const shouldError = Math.random() < errorChance;

            if (shouldError && /[a-zA-Z0-9]/.test(char)) {
                const typo = adjacentTypo(char);
                if (typo) {
                    typeChar(typo, input);
                    charsTypedCount++;
                    charsTypedEl.textContent = charsTypedCount;
                    await new Promise(r => setTimeout(r, baseDelay * (0.4 + Math.random() * 0.3)));

                    // 25% chance: notice the mistake 1-2 chars later instead of immediately
                    if (Math.random() < 0.25 && i + 2 < text.length) {
                        pendingBackspaceAt = i + 1 + Math.floor(Math.random() * 2);
                        // Type the correct char now and carry on; correction comes later
                    } else {
                        // Immediate correction
                        const bsOpts = { key:'Backspace', code:'Backspace', keyCode:8, which:8,
                                         bubbles:true, cancelable:true, view:window };
                        await new Promise(r => setTimeout(r, 80 + Math.random() * 120));
                        input.dispatchEvent(new KeyboardEvent('keydown',  bsOpts));
                        input.dispatchEvent(new KeyboardEvent('keypress', bsOpts));
                        input.value = input.value.slice(0, -1);
                        input.dispatchEvent(new Event('input',  { bubbles:true }));
                        input.dispatchEvent(new Event('change', { bubbles:true }));
                        input.dispatchEvent(new KeyboardEvent('keyup', bsOpts));
                        await new Promise(r => setTimeout(r, 150 + Math.random() * 150));
                    }
                    cautionCharsLeft = 3 + Math.floor(Math.random() * 3);
                }
            }

            typeChar(char, input);
            charsTypedCount++;
            charsTypedEl.textContent = charsTypedCount;

            // ── Per-character delay ───────────────────────────────────────────
            let delay = baseDelay * burstMult * (0.75 + Math.random() * 0.5);

            // Punctuation pauses
            if (['.', '!', '?'].includes(char))       delay *= 2.2;
            else if ([',', ';', ':'].includes(char))  delay *= 1.6;
            else if (char === '\n')                  delay *= 2.5;
            // Inter-word pause
            else if (char === ' ') {
                delay *= 1.4;
                // Extra pause before a new sentence (next char is uppercase)
                const next = text[i + 1];
                if (next && next === next.toUpperCase() && /[A-Z]/.test(next)) {
                    delay += 60 + Math.random() * 80;
                }
            }

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
