import * as THREE from "three";
export function makeArt(type: number): HTMLCanvasElement {
    const canvas = document.createElement('canvas');
    canvas.width = 1000;
    canvas.height = 720;
    const c = canvas.getContext('2d')!;
    c.fillStyle = '#0b0e16';
    c.fillRect(0, 0, 1000, 720);
    if (type === 0) {
        const halo = c.createRadialGradient(530, 380, 40, 530, 380, 420);
        halo.addColorStop(0, '#143cf2');
        halo.addColorStop(.65, '#0c1648');
        halo.addColorStop(1, '#070a10');
        c.fillStyle = halo;
        c.fillRect(0, 0, 1000, 720);
        for (let j = 0; j < 95; j++) {
            const p = j / 95;
            c.beginPath();
            for (let k = 0; k <= 150; k++) {
                const a = k / 150 * Math.PI * 2;
                const wave = Math.sin(a * 3 + p * 5) * 24;
                const x = 520 + Math.cos(a) * (255 + wave) * Math.sin(p * Math.PI);
                const y = 354 + Math.sin(a) * (246 + wave) * Math.sin(p * Math.PI) + Math.cos(p * Math.PI) * 65;
                if (k === 0)
                    c.moveTo(x, y);
                else
                    c.lineTo(x, y);
            }
            c.strokeStyle = `rgba(${110 + j},${155 + j},255,${.22 + .65 * Math.sin(p * Math.PI)})`;
            c.lineWidth = 1.25;
            c.stroke();
        }
        c.font = '500 15px sans-serif';
        c.fillStyle = '#8daaff';
        c.fillText('EXPERIMENTS IN LIGHT', 44, 54);
        c.font = 'bold 76px sans-serif';
        c.fillStyle = '#fff';
        c.fillText('CHROMATIC', 39, 649);
        c.font = '16px sans-serif';
        c.fillStyle = '#8c9ed1';
        c.fillText('001 / FORM WITHOUT LIMITS', 44, 685);
    }
    else if (type === 1) {
        c.fillStyle = '#050709';
        c.fillRect(0, 0, 1000, 720);
        for (let j = 0; j < 90; j++) {
            c.beginPath();
            for (let x = 0; x <= 1000; x += 6) {
                const y = 210 + j * 3 + Math.sin(x * .006 + j * .032) * 110 + Math.sin(x * .011 - j * .09) * 55;
                if (x === 0)
                    c.moveTo(x, y);
                else
                    c.lineTo(x, y);
            }
            c.strokeStyle = `hsla(${205 + j * .5},85%,${40 + j * .4}%,.8)`;
            c.lineWidth = 1;
            c.stroke();
        }
        c.font = '600 70px sans-serif';
        c.fillStyle = '#e9f1ff';
        c.fillText('Go with', 50, 565);
        c.fillText('the flow.', 50, 645);
        c.font = '14px sans-serif';
        c.fillStyle = '#789dc6';
        c.fillText('FLUID SYSTEMS / 002', 50, 55);
    }
    else if (type === 2) {
        c.fillStyle = '#eaeef5';
        c.fillRect(0, 0, 1000, 720);
        c.fillStyle = '#0b1125';
        c.font = 'bold 155px sans-serif';
        c.fillText('MAKE', 48, 246);
        c.fillText('ROOM.', 48, 395);
        c.fillStyle = '#2c5dff';
        c.fillRect(50, 443, 900, 4);
        c.font = '22px sans-serif';
        c.fillStyle = '#2a3b66';
        c.fillText('FOR THE NEXT BIG THING.', 52, 512);
        c.font = '15px sans-serif';
        c.fillText('TYPOGRAPHY STUDY', 52, 65);
        c.fillText('03 / PINBOARDSHOT', 52, 670);
        c.fillStyle = '#275dff';
        c.beginPath();
        c.arc(860, 600, 55, 0, Math.PI * 2);
        c.fill();
    }
    else if (type === 3) {
        c.fillStyle = '#101622';
        c.fillRect(0, 0, 1000, 720);
        c.font = '20px monospace';
        c.fillStyle = '#9bafda';
        c.fillText('workspace / capture.ts', 40, 60);
        c.fillStyle = '#202e49';
        c.fillRect(0, 90, 1000, 1);
        const code = ['const inspiration = capture({', '  source: "your screen",', '  quality: "retina",', '  possibilities: Infinity', '});', '', 'await inspiration', '  .annotate("the good part")', '  .pin({ alwaysOnTop: true });'];
        code.forEach((line, i) => { c.font = '25px monospace'; c.fillStyle = '#354561'; c.fillText(String(i + 1).padStart(2, '0'), 32, 153 + i * 48); c.fillStyle = ['#98aaff', '#77cfed', '#77cfed', '#9fa8ff', '#dae6ff', '#ccc', '#aabaff', '#77cfed', '#77cfed'][i]; c.fillText(line, 100, 153 + i * 48); });
    }
    else if (type === 4) {
        const g = c.createLinearGradient(0, 0, 1000, 720);
        g.addColorStop(0, '#3c1a79');
        g.addColorStop(.35, '#7737d7');
        g.addColorStop(.65, '#ff784c');
        g.addColorStop(1, '#ffe1ac');
        c.fillStyle = g;
        c.fillRect(0, 0, 1000, 720);
        for (let i = 0; i < 38; i++) {
            c.strokeStyle = `rgba(255,225,229,${.04 + i * .004})`;
            c.lineWidth = 2;
            c.beginPath();
            c.ellipse(600, 330, 90 + i * 14, 80 + i * 9, -.5, 0, Math.PI * 2);
            c.stroke();
        }
        c.fillStyle = 'white';
        c.font = 'bold 77px sans-serif';
        c.fillText('AFTER HOURS', 45, 640);
        c.font = '17px sans-serif';
        c.fillText('COLOR STUDY / 004', 45, 57);
    }
    else {
        c.fillStyle = '#101523';
        c.fillRect(0, 0, 1000, 720);
        ['#e5efff', '#799fff', '#356aff', '#263b9b', '#161d3b'].forEach((color, i) => { c.fillStyle = color; c.fillRect(40 + i * 187, 170, 175, 360); });
        c.fillStyle = '#e5edff';
        c.font = '30px sans-serif';
        c.fillText('A new spectrum.', 40, 98);
        c.font = '15px sans-serif';
        c.fillStyle = '#7a8bad';
        c.fillText('BLUE HOUR / BRAND PALETTE', 40, 645);
    }
    return canvas;
}
export function cardTexture(art: HTMLCanvasElement, index: number): THREE.CanvasTexture {
    const canvas = document.createElement('canvas');
    canvas.width = 1040;
    canvas.height = 800;
    const c = canvas.getContext('2d')!;
    c.beginPath();
    c.roundRect(0, 0, 1040, 800, 22);
    c.clip();
    c.fillStyle = '#1c2333';
    c.fillRect(0, 0, 1040, 800);
    c.fillStyle = '#6c8ed9';
    c.beginPath();
    c.arc(24, 21, 4, 0, Math.PI * 2);
    c.fill();
    c.fillStyle = '#a5b4d2';
    c.font = '13px sans-serif';
    c.fillText(['Chromatic — 001', 'Fluid — 002', 'Type — 003', 'Workspace — 004', 'After hours — 005', 'Spectrum — 006'][index], 38, 26);
    c.drawImage(art, 8, 40, 1024, 752);
    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    return texture;
}
