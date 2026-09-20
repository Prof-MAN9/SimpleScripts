// Typing Club Automator - FINAL (v5 - FULL AUTOMATION SUPPPORT)
// Set WPM +10 than target speed
(function() {
    'use strict';
    if (window.typingClubBot) {
        console.log('Bot already running! Close it first with: window.typingClubBot.close()');
        return;
    }

    console.log('🚀 Loading Typing Club Bot v4.6...');

    const gui = document.createElement('div');
    gui.id = 'typing-bot-gui';

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

    const speedSlider      = document.getElementById('speed-slider');
    const speedValue       = document.getElementById('speed-value');
    const accuracySlider   = document.getElementById('accuracy-slider');
    const accuracyValue    = document.getElementById('accuracy-value');
    const autoAdvance      = document.getElementById('auto-advance');
    const startBtn         = document.getElementById('start-btn');
    const stopBtn          = document.getElementById('stop-btn');
    const status           = document.getElementById('status');
    const levelInfo        = document.getElementById('level-info');
    const charsTypedEl     = document.getElementById('chars-typed');
    const levelsCompletedEl= document.getElementById('levels-completed');
    const closeBtn         = document.getElementById('bot-close');
    const header           = document.getElementById('bot-header');

    let botRunning      = false;
    let charsTypedCount = 0;
    let levelsCompleted = 0;

    speedSlider.addEventListener('input',    (e) => speedValue.textContent    = e.target.value);
    accuracySlider.addEventListener('input', (e) => accuracyValue.textContent = e.target.value);

    // ── Draggable ─────────────────────────────────────────────────────────────
    let isDragging = false, initialX, initialY;
    header.addEventListener('mousedown', (e) => {
        initialX = e.clientX - gui.offsetLeft;
        initialY = e.clientY - gui.offsetTop;
        isDragging = true;
    });
    document.addEventListener('mousemove', (e) => {
        if (!isDragging) return;
        e.preventDefault();
        gui.style.left  = (e.clientX - initialX) + 'px';
        gui.style.top   = (e.clientY - initialY) + 'px';
        gui.style.right = 'auto';
    });
    document.addEventListener('mouseup', () => isDragging = false);
    // ─────────────────────────────────────────────────────────────────────────


    // =========================================================================
    // ANCHOR KEY SUPPORT
    // =========================================================================
    //
    // Some TypingClub lessons use a "render_engine" of "right-anchor" or
    // "left-anchor".  Before typing begins an overlay appears:
    //   "Hold the <f> key while typing this lesson."
    //
    // TypingCore enforces this in _input_handler_keydown (student_1237_min.js):
    //
    //   if (this.anchor_key && !e.metaKey && !e.ctrlKey) {
    //       if (e.key.toLowerCase() == this.anchor_key) {
    //           this.is_anchoring = true;           // anchor confirmed
    //           e.preventDefault(); return;
    //       }
    //       if (!this.is_anchoring)
    //           e.preventDefault(); return;          // ALL other keys blocked
    //   }
    //
    // And in _input_handler_keyup:
    //   if (anchor_key matches) → is_anchoring = false  (blocks typing again)
    //
    // Strategy: fire one keydown(anchorKey) on the focusInput to set
    // is_anchoring = true, then keep re-firing every 50 ms so the core never
    // sees a keyup for the anchor key until we deliberately send one after the
    // lesson finishes.
    // =========================================================================

    // ── detectAnchorKey ───────────────────────────────────────────────────────
    // Returns the single character that must be held, or null if not an anchor
    // lesson.  Checks the DOM overlay first (most reliable), then falls back to
    // approuter.lesson.activity.render_engine.
    function detectAnchorKey() {
        // Primary: the .blackoverlay .keybtn span that shows the key name
        const overlayKey = document.querySelector('.blackoverlay .keybtn');
        if (overlayKey) {
            const k = overlayKey.textContent.trim().toLowerCase();
            if (k.length === 1) return k;
        }

        // Fallback: render_engine encodes the hand side
        // "right-anchor" → home key for right index finger = 'j'
        // "left-anchor"  → home key for left  index finger = 'f'
        try {
            const re = window.approuter?.lesson?.activity?.render_engine || '';
            if (re === 'right-anchor') return 'j';
            if (re === 'left-anchor')  return 'f';
        } catch (_) {}

        return null;
    }

    // ── startHoldingKey ───────────────────────────────────────────────────────
    // Fires an initial keydown on targetElement to set is_anchoring = true,
    // then keeps repeating every 50 ms.  Returns the interval ID so the caller
    // can stop it later.
    function startHoldingKey(key, targetElement) {
        if (!key) return null;
        const upper   = key.toUpperCase();
        const keyCode = key.charCodeAt(0);
        const opts = {
            key,
            code:       `Key${upper}`,
            keyCode,
            which:      keyCode,
            bubbles:    true,
            cancelable: true,
            composed:   true,
            view:       window,
        };

        // First press — sets is_anchoring = true inside TypingCore
        targetElement.dispatchEvent(new KeyboardEvent('keydown', opts));

        // Sustained repeat — keeps is_anchoring alive between keystrokes
        const intervalId = setInterval(() => {
            if (!botRunning) return;
            targetElement.dispatchEvent(new KeyboardEvent('keydown', { ...opts, repeat: true }));
        }, 50);

        console.log(`🔑 Holding anchor key: "${key}"`);
        return intervalId;
    }

    // ── stopHoldingKey ────────────────────────────────────────────────────────
    // Clears the repeat interval and fires a keyup so TypingCore's keyup handler
    // doesn't leave is_anchoring in a dangling state for the next lesson.
    function stopHoldingKey(key, targetElement, intervalId) {
        if (!key) return;
        if (intervalId !== null) clearInterval(intervalId);
        const upper   = key.toUpperCase();
        const keyCode = key.charCodeAt(0);
        targetElement.dispatchEvent(new KeyboardEvent('keyup', {
            key,
            code:       `Key${upper}`,
            keyCode,
            which:      keyCode,
            bubbles:    true,
            cancelable: true,
            composed:   true,
            view:       window,
        }));
        console.log(`🔓 Released anchor key: "${key}"`);
    }
    // =========================================================================
    // END ANCHOR KEY SUPPORT
    // =========================================================================


    // ── detectLevel ───────────────────────────────────────────────────────────
    function detectLevel() {
        // Instruction / intro screen — check FIRST.
        // The blackoverlay (anchor prompt) is NOT an instruction screen —
        // it appears alongside the typable content, not instead of it.
        // We only treat it as instruction if the navbar-continue button is
        // visible AND there is no typable content on the page yet.
        const continueBtn = document.querySelector('.navbar-continue');
        const hasTypable  = document.querySelectorAll('div.typable span.token_unit').length > 0
                         || document.querySelectorAll('.boxed-line .boxed-char').length > 0;

        if (continueBtn && continueBtn.offsetParent !== null && !hasTypable) {
            levelInfo.textContent = 'Instruction screen';
            return { text: null, type: 'instruction' };
        }

        // Boxed typing activity
        const boxedChars = document.querySelectorAll('.boxed-line .boxed-char');
        if (boxedChars.length > 0) {
            const text = Array.from(boxedChars).map(el => {
                const t = el.textContent;
                return (t === ' ' || t === '\u00a0') ? ' ' : t;
            }).join('');
            levelInfo.textContent = `Boxed: ${text.length} chars`;
            return { text, type: 'typing' };
        }

        // Standard token_unit lesson
        const letters = document.querySelectorAll('div.typable span.token_unit');
        if (letters && letters.length > 0) {
            const text = Array.from(letters).map(s => {
                if (s.querySelector('._enter') || s.querySelector('br')) return '\n';
                if (s.querySelector('i')) return ' ';
                return s.textContent;
            }).join('');
            levelInfo.textContent = `${text.length} chars detected`;
            return { text, type: 'typing' };
        }

        // Generic typable fallback
        const typable = document.querySelector('div.typable');
        if (typable && typable.textContent) {
            const text = typable.textContent.trim().replace(/\s+/g, ' ');
            levelInfo.textContent = `${text.length} chars detected`;
            return { text, type: 'typing' };
        }

        // Typing game via approuter
        try {
            const app = window.approuter?.lesson?.activity?.app;
            if (app && app.startsWith('typing.games.')) {
                const gameName = app.split('.')[2];
                levelInfo.textContent = `Game: ${gameName}`;
                return { text: null, type: 'game', gameName };
            }
        } catch (_) {}

        const gameContainer = document.querySelector('#game canvas, #game');
        if (gameContainer && gameContainer.style.display !== 'none') {
            levelInfo.textContent = 'Game detected';
            return { text: null, type: 'game', gameName: 'unknown' };
        }

        return { text: null, type: null };
    }


    // ── typeChar ──────────────────────────────────────────────────────────────
    function typeChar(char, field) {
        const keyCode = char.charCodeAt(0);
        let code     = 'Unidentified';
        let shiftKey = false;

        const specialChars = {
            ' ':  { code: 'Space',     keyCode: 32  },
            '\n': { code: 'Enter',     keyCode: 13  },
            '"':  { code: 'Quote',     keyCode: 222, shiftKey: true  },
            "'":  { code: 'Quote',     keyCode: 222, shiftKey: false },
            ',':  { code: 'Comma',     keyCode: 188 },
            '.':  { code: 'Period',    keyCode: 190 },
            '!':  { code: 'Digit1',    keyCode: 49,  shiftKey: true  },
            '?':  { code: 'Slash',     keyCode: 191, shiftKey: true  },
            ':':  { code: 'Semicolon', keyCode: 186, shiftKey: true  },
            ';':  { code: 'Semicolon', keyCode: 186 },
            '-':  { code: 'Minus',     keyCode: 189 },
            '(':  { code: 'Digit9',    keyCode: 57,  shiftKey: true  },
            ')':  { code: 'Digit0',    keyCode: 48,  shiftKey: true  },
        };

        if (specialChars[char]) {
            code     = specialChars[char].code;
            shiftKey = specialChars[char].shiftKey || false;
        } else if (/[a-z]/.test(char)) {
            code = `Key${char.toUpperCase()}`;
        } else if (/[A-Z]/.test(char)) {
            code     = `Key${char}`;
            shiftKey = true;
        } else if (/[0-9]/.test(char)) {
            code = `Digit${char}`;
        }

        const isEnter = (char === '\n' || char === '\r');
        const opts = {
            key:      isEnter ? 'Enter' : char,
            code,
            keyCode:  isEnter ? 13 : keyCode,
            which:    isEnter ? 13 : keyCode,
            shiftKey,
            bubbles:  true, cancelable: true, composed: true, view: window,
        };
        field.dispatchEvent(new KeyboardEvent('keydown',  opts));
        field.dispatchEvent(new KeyboardEvent('keypress', opts));
        if (!isEnter) {
            field.value += char;
            field.dispatchEvent(new Event('input',  { bubbles: true }));
            field.dispatchEvent(new Event('change', { bubbles: true }));
        }
        field.dispatchEvent(new KeyboardEvent('keyup', opts));
    }


    // ── Adjacent-key map ──────────────────────────────────────────────────────
    const ADJACENT_KEYS = {
        a:['s','q','w','z'],         b:['v','g','h','n'],         c:['x','d','f','v'],
        d:['s','e','r','f','c','x'], e:['w','r','d','s'],         f:['d','r','t','g','v','c'],
        g:['f','t','y','h','b','v'], h:['g','y','u','j','n','b'], i:['u','o','k','j'],
        j:['h','u','i','k','m','n'], k:['j','i','o','l','m'],     l:['k','o','p',';'],
        m:['n','j','k'],             n:['b','h','j','m'],          o:['i','p','l','k'],
        p:['o','l',';','['],         q:['w','a'],                  r:['e','t','f','d'],
        s:['a','w','e','d','x','z'], t:['r','y','g','f'],          u:['y','i','j','h'],
        v:['c','f','g','b'],         w:['q','e','s','a'],          x:['z','s','d','c'],
        y:['t','u','h','g'],         z:['a','s','x'],
        '1':['2','q'],  '2':['1','3','q','w'],  '3':['2','4','w','e'],
        '4':['3','5','e','r'],       '5':['4','6','r','t'],        '6':['5','7','t','y'],
        '7':['6','8','y','u'],       '8':['7','9','u','i'],        '9':['8','0','i','o'],
        '0':['9','p','o'],
        ',':['m','l','.'],  '.':['l',',','/'],  '/':['.',';','l'],
        ';':['l',"'",'p','/'],  "'":[';','[','p'],
    };

    function getAdjacentTypo(char) {
        const key       = char.toLowerCase();
        const neighbors = ADJACENT_KEYS[key];
        if (!neighbors || neighbors.length === 0) return null;
        const pick = neighbors[Math.floor(Math.random() * neighbors.length)];
        return char !== char.toLowerCase() ? pick.toUpperCase() : pick;
    }


    // ── typeWordToGame ────────────────────────────────────────────────────────
    async function typeWordToGame(word) {
        const wpm       = parseInt(speedSlider.value);
        const baseDelay = 60000 / (wpm * 5);

        // Path A: DEV_MODE / window.game (production no-op)
        const tryIdkfa = async () => {
            try {
                const g = window.game;
                if (g?.state) {
                    const st = g.state.states[g.state.current];
                    if (typeof st?.core?.record_keydown_time === 'function') {
                        for (const char of word) {
                            st.core.record_keydown_time(char);
                            await new Promise(r => setTimeout(r, baseDelay * (0.8 + Math.random() * 0.4)));
                        }
                        return true;
                    }
                }
            } catch (_) {}
            return false;
        };

        if (await tryIdkfa()) {
            charsTypedCount += word.length;
            charsTypedEl.textContent = charsTypedCount;
            return true;
        }

        // Path B: hidden focusInput (standard desktop path)
        const focusInput = document.querySelector("body > input[type='text'][aria-hidden='true']");
        if (focusInput) {
            focusInput.focus();
            for (const char of word) {
                if (!botRunning) return false;
                const upper   = char.toUpperCase();
                const keyCode = /[a-zA-Z]/.test(char) ? upper.charCodeAt(0) : char.charCodeAt(0);
                const keyOpts = {
                    key:        char,
                    code:       /[a-zA-Z]/.test(char) ? `Key${upper}` : 'Unidentified',
                    keyCode, which: keyCode,
                    bubbles: true, cancelable: true, composed: true, view: window,
                };
                focusInput.dispatchEvent(new KeyboardEvent('keydown', keyOpts));
                focusInput.value = char;
                focusInput.dispatchEvent(new Event('input', { bubbles: true }));
                focusInput.dispatchEvent(new KeyboardEvent('keyup', keyOpts));
                charsTypedCount++;
                charsTypedEl.textContent = charsTypedCount;
                await new Promise(r => setTimeout(r, baseDelay * (0.8 + Math.random() * 0.4)));
            }
            return true;
        }

        // Path C: document keypress fallback (iOS / no_input_mode)
        console.warn('⚠️ focusInput not found — falling back to document keypress');
        for (const char of word) {
            if (!botRunning) return false;
            const keyCode = char.charCodeAt(0);
            document.dispatchEvent(new KeyboardEvent('keypress', {
                key: char, keyCode, which: keyCode, charCode: keyCode,
                bubbles: true, cancelable: true, composed: true, view: window,
            }));
            charsTypedCount++;
            charsTypedEl.textContent = charsTypedCount;
            await new Promise(r => setTimeout(r, baseDelay * (0.8 + Math.random() * 0.4)));
        }
        return true;
    }


    // ── processTypingGame ─────────────────────────────────────────────────────
    async function processTypingGame(gameName) {
        console.log(`🎮 Typing game detected: ${gameName}`);
        status.textContent = `🎮 ${gameName}…`;

        // 1. Load lesson words
        let lessonWords = [];
        try {
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
                console.warn('⚠️ lesson_text not found. approuter snapshot:',
                    JSON.stringify({
                        keys:         Object.keys(window.approuter || {}),
                        detailsKeys:  Object.keys(window.approuter?.details || {}),
                        lessonKeys:   Object.keys(window.approuter?.lesson || {}),
                        activityKeys: Object.keys(window.approuter?.lesson?.activity || {}),
                    }, null, 2));
            }
        } catch (_) {}
        const lessonSet = new Set(lessonWords.map(w => w.toLowerCase()));

        // 2. fillText intercept (Tier 1)
        const wordQueue  = [];
        const recentSeen = new Map();
        const DEDUP_MS   = 3500;
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

        // 3. Game-done check
        const isGameDone = () => {
            const el = document.querySelector('#game');
            return !el || el.style.display === 'none'
                || !!window.approuter?.modelManager?._attempt;
        };

        // 4. Wait for canvas
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
        await new Promise(r => setTimeout(r, 800));

        // 5. Spacebar to start game
        const spaceOpts = { key: ' ', code: 'Space', keyCode: 32, which: 32,
                            bubbles: true, cancelable: true, view: window };
        document.dispatchEvent(new KeyboardEvent('keydown', spaceOpts));
        document.dispatchEvent(new KeyboardEvent('keyup',   spaceOpts));
        console.log('⎵ Spacebar sent — waiting for first words to spawn…');
        await new Promise(r => setTimeout(r, 700));

        // 6. 3-second probe for fillText words
        status.textContent = `🎮 ${gameName} — detecting words…`;
        const probeEnd = Date.now() + 3000;
        while (botRunning && !isGameDone() && wordQueue.length === 0 && Date.now() < probeEnd) {
            await new Promise(r => setTimeout(r, 150));
        }

        // 7. Tier-2 fallback
        let directWordIndex = 0;
        let isDirectMode    = false;
        if (wordQueue.length === 0) {
            if (lessonWords.length === 0) {
                unhook();
                status.textContent = '⚠️ No words — cannot read approuter.lesson';
                console.error('❌ lessonWords empty and fillText yielded nothing');
                stopBot();
                return;
            }
            isDirectMode = true;
            console.log(`ℹ️ fillText inactive — direct mode (${lessonWords.length} words)`);
            status.textContent = `📝 Direct mode: ${lessonWords.length} words`;
            wordQueue.push(lessonWords[directWordIndex++] || '');
            if (lessonWords[directWordIndex]) wordQueue.push(lessonWords[directWordIndex++]);
        }

        // 8. Main game typing loop
        let staleTicks = 0;
        const TICK_MS  = 100, MAX_STALE = 300;
        while (botRunning) {
            if (isGameDone()) break;
            if (wordQueue.length > 0) {
                staleTicks = 0;
                const word = wordQueue.shift();
                recentSeen.set(word.toLowerCase(), Date.now());
                status.textContent = `⌨️ "${word}"`;
                console.log(`⌨️ Typing: "${word}"`);
                await typeWordToGame(word);
                await new Promise(r => setTimeout(r, 180 + Math.random() * 120));
                if (isDirectMode && directWordIndex < lessonWords.length) {
                    wordQueue.push(lessonWords[directWordIndex++]);
                } else if (isDirectMode && directWordIndex >= lessonWords.length) {
                    directWordIndex = 0;
                    console.log('🔄 Direct mode: restarting word list…');
                    wordQueue.push(lessonWords[directWordIndex++]);
                }
            } else {
                staleTicks++;
                if (staleTicks >= MAX_STALE) {
                    console.warn('⏳ Queue empty for ~30 s — assuming game complete');
                    break;
                }
                await new Promise(r => setTimeout(r, TICK_MS));
            }
        }

        // 9. Level complete
        unhook();
        console.log(`✅ Game complete: ${gameName}`);
        levelsCompleted++;
        levelsCompletedEl.textContent = levelsCompleted;
        status.textContent = '✅ Game complete!';

        if (autoAdvance.checked) {
            await new Promise(r => setTimeout(r, 4000));
            const enterOpts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13,
                                bubbles: true, cancelable: true, view: window };
            document.dispatchEvent(new KeyboardEvent('keydown', enterOpts));
            document.dispatchEvent(new KeyboardEvent('keyup',   enterOpts));
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


    // ── processLevel ──────────────────────────────────────────────────────────
    async function processLevel() {
        if (!botRunning) return;

        const level = detectLevel();

        if (!level.text && level.type !== 'game' && level.type !== 'instruction') {
            status.textContent = '⚠️ No text or game found';
            console.log('❌ Could not find text or game');
            stopBot();
            return;
        }

        // Instruction screen
        if (level.type === 'instruction') {
            status.textContent = '⏭ Skipping instruction…';
            console.log('📖 Instruction screen — pressing Enter');
            await new Promise(r => setTimeout(r, 800));
            const enterOpts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13,
                                bubbles: true, cancelable: true, view: window };
            const btn = document.querySelector('.navbar-continue');
            if (btn) btn.click();
            document.dispatchEvent(new KeyboardEvent('keydown', enterOpts));
            document.dispatchEvent(new KeyboardEvent('keyup',   enterOpts));
            await new Promise(r => setTimeout(r, 1500));
            if (botRunning) processLevel();
            return;
        }

        // Typing game
        if (level.type === 'game') {
            await processTypingGame(level.gameName || 'unknown');
            return;
        }

        // ── Standard typing lesson ────────────────────────────────────────────
        const text = level.text;
        console.log('📝 Text:', text);
        status.textContent = '👆 Starting lesson...';

        const typingArea = document.querySelector('.tpmodes, .typable, .inview');
        if (typingArea) typingArea.click();
        document.body.click();
        document.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', keyCode: 32, bubbles: true }));
        await new Promise(r => setTimeout(r, 500));

        // Find the TypingCore hidden focus input
        let input = null;
        for (let attempt = 0; attempt < 30; attempt++) {
            input = document.querySelector("body > input[type='text'][aria-hidden='true']")
                 || document.querySelector("input[type='text'][aria-hidden='true']");
            if (input) break;
            await new Promise(r => setTimeout(r, 100));
        }
        if (!input) {
            status.textContent = '⚠️ Input not found';
            console.log('❌ No input field found');
            stopBot();
            return;
        }

        input.value = '';
        input.focus();
        await new Promise(r => setTimeout(r, 100));

        // ── ANCHOR KEY: detect and begin holding ─────────────────────────────
        // detectAnchorKey() checks both the DOM overlay (.blackoverlay .keybtn)
        // and the approuter render_engine fallback.  If an anchor is required,
        // we dismiss the overlay (if visible) then start holding the key on the
        // focusInput before any typing character is dispatched.
        const anchorKey      = detectAnchorKey();
        let   anchorInterval = null;

        if (anchorKey) {
            console.log(`🔑 Anchor lesson — key: "${anchorKey}"`);
            status.textContent = `🔑 Holding "${anchorKey.toUpperCase()}" + typing…`;

            // Dismiss the overlay by clicking the continue button if shown.
            // On anchor lessons the overlay appears before the lesson starts;
            // clicking the button (or pressing Enter) starts the clock and
            // hides the overlay so the typable content becomes active.
            const continueBtn = document.querySelector('.navbar-continue');
            if (continueBtn && continueBtn.offsetParent !== null) {
                continueBtn.click();
                await new Promise(r => setTimeout(r, 600));
                // Re-focus after the click may have shifted focus away
                input.focus();
            }

            // Begin holding — sets is_anchoring = true in TypingCore
            anchorInterval = startHoldingKey(anchorKey, input);

            // Wait 150 ms for is_anchoring to register before the first
            // character keystroke arrives
            await new Promise(r => setTimeout(r, 150));
        }
        // ─────────────────────────────────────────────────────────────────────

        const wpm       = parseInt(speedSlider.value);
        const accuracy  = parseInt(accuracySlider.value);
        const baseDelay = 60000 / (wpm * 5);
        status.textContent = anchorKey
            ? `🔑 "${anchorKey.toUpperCase()}" held — typing…`
            : '⌨️ Typing...';

        let burstMultiplier = 1.0;
        let burstCharsLeft  = 0;

        for (let i = 0; i < text.length; i++) {
            if (!botRunning) {
                // Always release anchor if bot is stopped mid-lesson
                if (anchorKey && anchorInterval !== null) {
                    stopHoldingKey(anchorKey, input, anchorInterval);
                    anchorInterval = null;
                }
                return;
            }

            // Burst rhythm
            if (burstCharsLeft <= 0) {
                const roll = Math.random();
                if      (roll < 0.35) { burstMultiplier = 0.5 + Math.random() * 0.3; }
                else if (roll < 0.65) { burstMultiplier = 0.9 + Math.random() * 0.2; }
                else                  { burstMultiplier = 1.2 + Math.random() * 0.7; }
                burstCharsLeft = 3 + Math.floor(Math.random() * 8);
            }
            burstCharsLeft--;

            const char      = text[i];
            const shouldErr = Math.random() * 100 > accuracy;
            const typo      = (shouldErr && /[a-zA-Z0-9,.\/;']/.test(char))
                            ? getAdjacentTypo(char) : null;

            if (typo) {
                typeChar(typo, input);
                await new Promise(r => setTimeout(r, baseDelay * 0.5));
                const bsOpts = { key: 'Backspace', code: 'Backspace', keyCode: 8, which: 8,
                                 bubbles: true, cancelable: true, view: window };
                input.dispatchEvent(new KeyboardEvent('keydown',  bsOpts));
                input.dispatchEvent(new KeyboardEvent('keypress', bsOpts));
                input.value = input.value.slice(0, -1);
                input.dispatchEvent(new Event('input',  { bubbles: true }));
                input.dispatchEvent(new Event('change', { bubbles: true }));
                input.dispatchEvent(new KeyboardEvent('keyup', bsOpts));
                await new Promise(r => setTimeout(r, 300));
            }

            typeChar(char, input);
            charsTypedCount++;
            charsTypedEl.textContent = charsTypedCount;

            let delay = baseDelay * burstMultiplier * (0.8 + Math.random() * 0.4);
            if (['.', '!', '?'].includes(char)) delay *= 2;
            else if (char === ' ')              delay *= 1.3;
            await new Promise(r => setTimeout(r, delay));
        }

        // ── ANCHOR KEY: release after all characters are typed ────────────────
        if (anchorKey && anchorInterval !== null) {
            stopHoldingKey(anchorKey, input, anchorInterval);
            anchorInterval = null;
        }
        // ─────────────────────────────────────────────────────────────────────

        console.log('✅ Complete!');
        levelsCompleted++;
        levelsCompletedEl.textContent = levelsCompleted;
        status.textContent = '✅ Complete! Waiting...';

        if (autoAdvance.checked) {
            await new Promise(r => setTimeout(r, 6000));
            const enterOpts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13,
                                bubbles: true, cancelable: true, view: window };
            document.dispatchEvent(new KeyboardEvent('keydown',  enterOpts));
            document.dispatchEvent(new KeyboardEvent('keypress', enterOpts));
            document.dispatchEvent(new KeyboardEvent('keyup',    enterOpts));
            if (input) {
                input.dispatchEvent(new KeyboardEvent('keydown',  enterOpts));
                input.dispatchEvent(new KeyboardEvent('keypress', enterOpts));
                input.dispatchEvent(new KeyboardEvent('keyup',    enterOpts));
            }
            document.body.dispatchEvent(new KeyboardEvent('keydown',  enterOpts));
            document.body.dispatchEvent(new KeyboardEvent('keypress', enterOpts));
            document.body.dispatchEvent(new KeyboardEvent('keyup',    enterOpts));
            document.body.click();
            const centerEl = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
            if (centerEl && !centerEl.closest('#typing-bot-gui')) centerEl.click();
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


    // ── Bot controls ──────────────────────────────────────────────────────────
    function startBot() {
        botRunning = true;
        startBtn.disabled    = true;
        startBtn.style.opacity = '0.5';
        stopBtn.disabled     = false;
        stopBtn.style.opacity  = '1';
        console.log('🤖 Bot started');
        processLevel();
    }

    function stopBot() {
        botRunning = false;
        startBtn.disabled    = false;
        startBtn.style.opacity = '1';
        stopBtn.disabled     = true;
        stopBtn.style.opacity  = '0.5';
        status.textContent = '⏹ Stopped';
    }

    function closeBot() {
        stopBot();
        gui.remove();
        window.typingClubBot = null;
    }

    startBtn.addEventListener('click', startBot);
    stopBtn.addEventListener('click',  stopBot);
    closeBtn.addEventListener('click', closeBot);

    window.typingClubBot = { start: startBot, stop: stopBot, close: closeBot };

    setTimeout(detectLevel, 500);
    console.log('✅ Bot v4.6 loaded! Click Start Bot.');
})();
