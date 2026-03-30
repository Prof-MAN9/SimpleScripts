// Typing Club Automator - AUTO START (v3 - ENTER Patched)
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

        const gameContainer = document.querySelector('.game-container, .game-canvas, canvas, #game, [class*="game"]');
        if (gameContainer) {
            levelInfo.textContent = 'Game detected';
            return { text: null, type: 'game' };
        }

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

    async function processLevel() {
        if (!botRunning) return;

        const level = detectLevel();

        if (!level.text && level.type !== 'game') {
            status.textContent = '⚠️ No text or game found';
            console.log('❌ Could not find text or game');
            stopBot();
            return;
        }

        if (level.type === 'game') {
            console.log('🎮 Game detected, auto-playing...');
            status.textContent = '🎮 Playing game...';
            await new Promise(r => setTimeout(r, 2000));
            const gameKeys = ['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Enter', 'KeyW', 'KeyA', 'KeyS', 'KeyD'];
            
            for (let i = 0; i < 50; i++) {
                if (!botRunning) return;
                const randomKey = gameKeys[Math.floor(Math.random() * gameKeys.length)];
                const keyOpts = {
                    key: randomKey.includes('Arrow') || randomKey.includes('Space') ? randomKey.replace('Arrow', '').replace('Key', '') : randomKey.replace('Key', '').toLowerCase(),
                    code: randomKey,
                    keyCode: randomKey === 'Space' ? 32 : randomKey.includes('Arrow') ? (randomKey === 'ArrowUp' ? 38 : randomKey === 'ArrowDown' ? 40 : randomKey === 'ArrowLeft' ? 37 : 39) : randomKey.charCodeAt(3),
                    bubbles: true, cancelable: true, view: window
                };
                document.dispatchEvent(new KeyboardEvent('keydown', keyOpts));
                document.dispatchEvent(new KeyboardEvent('keyup', keyOpts));
                if (i % 5 === 0) {
                    const x = Math.random() * window.innerWidth;
                    const y = Math.random() * window.innerHeight;
                    const el = document.elementFromPoint(x, y);
                    if (el && !el.closest('#typing-bot-gui')) { el.click(); }
                }
                await new Promise(r => setTimeout(r, 100));
            }
            console.log('🎮 Game sequence complete');
            status.textContent = '✅ Game complete!';
            if (autoAdvance.checked) {
                await new Promise(r => setTimeout(r, 6000));
                document.body.click();
                const clickables = document.querySelectorAll('button, .btn, [role="button"]');
                clickables.forEach(el => { if (el.offsetParent !== null && !el.closest('#typing-bot-gui')) { el.click(); } });
                await new Promise(r => setTimeout(r, 1000));
                if (botRunning) processLevel();
            } else { stopBot(); }
            return;
        }

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
