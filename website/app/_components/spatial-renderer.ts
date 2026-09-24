import * as THREE from "three";
import { cardTexture, makeArt } from "./spatial-art";
export interface SpatialController {
    setExpanded(expanded: boolean): void;
    setPaused(paused: boolean): void;
    dispose(): void;
}
export function createSpatialRenderer(host: HTMLElement, onUnavailable: () => void): SpatialController {
    const renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true });
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(36, 1, 0.1, 100);
    const group = new THREE.Group();
    const orbit = new THREE.Group();
    const cards: THREE.Mesh[] = [];
    const markers: THREE.Sprite[] = [];
    const pointer = new THREE.Vector2();
    const positions = [
        [-.25, .08, 1.3, .04, -.09, -.12, 1.02], [-3.65, .5, -.6, .1, .35, .15, .74],
        [3.7, .92, -1.1, -.12, -.38, -.13, .65], [3.3, -1.3, -.1, .12, -.22, .15, .69],
        [-3.08, -1.53, -.3, .04, .24, -.13, .64], [.65, 1.76, -1.8, .12, -.12, .07, .57],
    ];
    let disposed = false;
    let paused = true;
    let visible = true;
    let frame = 0;
    let lastTime = 0;
    let time = 0;
    let spread = 0;
    let targetSpread = 1;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.75));
    renderer.setClearColor(0, 0);
    renderer.domElement.setAttribute("aria-hidden", "true");
    host.append(renderer.domElement);
    scene.add(group, orbit);
    orbit.rotation.set(.95, -.2, -.16);
    orbit.position.z = -1.3;
    function requestFrame() {
        if (!disposed && visible && !document.hidden && !frame)
            frame = requestAnimationFrame(draw);
    }
    function draw(now: number) {
        frame = 0;
        const delta = Math.min((now - lastTime) / 1000 || 0, .04);
        lastTime = now;
        if (!paused)
            time += delta;
        const ease = paused ? 1 : 1 - Math.exp(-delta * 4.8);
        spread += (targetSpread - spread) * ease;
        group.rotation.y += ((paused ? 0 : pointer.x * .17) - group.rotation.y) * ease;
        group.rotation.x += ((paused ? 0 : -pointer.y * .07) - group.rotation.x) * ease;
        cards.forEach((card, index) => {
            const p = positions[index];
            const drift = paused ? 0 : Math.sin(time * .65 + index * 1.9) * .095 * spread;
            card.position.set(p[0] * spread, p[1] * spread + drift, p[2] * spread + (1 - spread) * (1.3 - index * .17));
            card.rotation.set(p[3] * spread, p[4] * spread, p[5] * spread + (1 - spread) * index * .025);
            card.scale.setScalar(1 + (p[6] - 1) * spread);
        });
        orbit.rotation.z = -.16 + Math.sin(time * .14) * .16;
        orbit.scale.setScalar(.8 + spread * .2);
        markers.forEach((marker, index) => {
            const angle = time * .22 + index * Math.PI * .5;
            marker.position.set(Math.cos(angle) * 3.8, Math.sin(angle) * 3.8, 0);
        });
        renderer.render(scene, camera);
        if (!paused)
            requestFrame();
    }
    function resize() {
        const { width, height } = host.getBoundingClientRect();
        if (!width || !height)
            return;
        renderer.setSize(width, height);
        camera.aspect = width / height;
        camera.position.z = Math.max(8.5, 11.8 / (2 * Math.tan(THREE.MathUtils.degToRad(18)) * camera.aspect));
        camera.updateProjectionMatrix();
        requestFrame();
    }
    function move(event: PointerEvent) {
        const rect = host.getBoundingClientRect();
        pointer.set((event.clientX - rect.left) / rect.width * 2 - 1, (event.clientY - rect.top) / rect.height * 2 - 1);
        requestFrame();
    }
    function leave() { pointer.set(0, 0); requestFrame(); }
    function stop() { cancelAnimationFrame(frame); frame = 0; }
    function visibilityChanged() {
        if (document.hidden)
            stop();
        else {
            lastTime = performance.now();
            requestFrame();
        }
    }
    function contextLost(event: Event) {
        event.preventDefault();
        dispose();
        onUnavailable();
    }
    const resizeObserver = new ResizeObserver(resize);
    const intersectionObserver = new IntersectionObserver(([entry]) => {
        visible = entry.isIntersecting;
        if (visible) {
            lastTime = performance.now();
            requestFrame();
        }
        else
            stop();
    }, { threshold: .01 });
    function dispose() {
        if (disposed)
            return;
        disposed = true;
        stop();
        resizeObserver.disconnect();
        intersectionObserver.disconnect();
        host.removeEventListener("pointermove", move);
        host.removeEventListener("pointerleave", leave);
        document.removeEventListener("visibilitychange", visibilityChanged);
        renderer.domElement.removeEventListener("webglcontextlost", contextLost);
        // Routes can mount this scene repeatedly; release shared GPU resources exactly once.
        const geometries = new Set<THREE.BufferGeometry>();
        const materials = new Set<THREE.Material>();
        const textures = new Set<THREE.Texture>();
        scene.traverse(object => {
            if (object instanceof THREE.Mesh || object instanceof THREE.Line || object instanceof THREE.Points || object instanceof THREE.Sprite) {
                if ("geometry" in object)
                    geometries.add(object.geometry);
                const objectMaterials = Array.isArray(object.material) ? object.material : [object.material];
                objectMaterials.forEach(material => {
                    materials.add(material);
                    if ("map" in material && material.map instanceof THREE.Texture)
                        textures.add(material.map);
                });
            }
        });
        textures.forEach(texture => texture.dispose());
        materials.forEach(material => material.dispose());
        geometries.forEach(geometry => geometry.dispose());
        renderer.dispose();
        renderer.domElement.remove();
    }
    try {
        const front = new THREE.PlaneGeometry(3.8, 2.92);
        for (let index = 0; index < 6; index++) {
            const mesh = new THREE.Mesh(front, new THREE.MeshBasicMaterial({ map: cardTexture(makeArt(index), index), transparent: true, side: THREE.DoubleSide }));
            cards.push(mesh);
            group.add(mesh);
            const box = new THREE.BoxGeometry(3.81, 2.93, .045);
            const edgeGeometry = new THREE.EdgesGeometry(box);
            box.dispose();
            const edge = new THREE.LineSegments(edgeGeometry, new THREE.LineBasicMaterial({ color: index === 0 ? 0x83b8ff : 0x385887, transparent: true, opacity: index === 0 ? .75 : .5 }));
            edge.position.z = -.025;
            mesh.add(edge);
        }
        for (let index = 0; index < 3; index++) {
            orbit.add(new THREE.Mesh(new THREE.TorusGeometry(3.8 + index * .19, index === 0 ? .013 : .004, 8, 180), new THREE.MeshBasicMaterial({ color: index === 0 ? 0x6a99ff : 0x386aff, transparent: true, opacity: index === 0 ? .72 : .2 })));
        }
        const canvas = document.createElement("canvas");
        canvas.width = canvas.height = 64;
        const context = canvas.getContext("2d")!;
        const gradient = context.createRadialGradient(32, 32, 0, 32, 32, 32);
        gradient.addColorStop(0, "#d9f7ff");
        gradient.addColorStop(.12, "#679aff");
        gradient.addColorStop(.35, "#3469ff80");
        gradient.addColorStop(1, "#2255ff00");
        context.fillStyle = gradient;
        context.fillRect(0, 0, 64, 64);
        const glow = new THREE.CanvasTexture(canvas);
        for (let index = 0; index < 4; index++) {
            const marker = new THREE.Sprite(new THREE.SpriteMaterial({ map: glow, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }));
            marker.scale.setScalar(.4);
            orbit.add(marker);
            markers.push(marker);
        }
        const dots = [];
        for (let index = 0; index < 100; index++)
            dots.push((Math.random() - .5) * 16, (Math.random() - .5) * 7, -2 - Math.random() * 3);
        const stars = new THREE.BufferGeometry();
        stars.setAttribute("position", new THREE.Float32BufferAttribute(dots, 3));
        scene.add(new THREE.Points(stars, new THREE.PointsMaterial({ size: .045, map: glow, transparent: true, opacity: .5, depthWrite: false, color: 0x6a9eff, blending: THREE.AdditiveBlending })));
        host.addEventListener("pointermove", move);
        host.addEventListener("pointerleave", leave);
        document.addEventListener("visibilitychange", visibilityChanged);
        renderer.domElement.addEventListener("webglcontextlost", contextLost);
        resizeObserver.observe(host);
        intersectionObserver.observe(host);
        resize();
    }
    catch (error) {
        dispose();
        throw error;
    }
    return {
        setExpanded(expanded) { targetSpread = expanded ? 1 : 0; requestFrame(); },
        setPaused(value) { paused = value; lastTime = performance.now(); requestFrame(); },
        dispose,
    };
}
