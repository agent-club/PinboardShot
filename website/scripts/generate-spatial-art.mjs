import { writeFile, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
const output = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../public/showcase");
await mkdir(output,{recursive:true});
const f = value => value.toFixed(2);
let paths="";
for(let j=0;j<95;j++){
 const p=j/95;let d="";
 for(let k=0;k<=150;k++){const a=k/150*Math.PI*2;const wave=Math.sin(a*3+p*5)*24;const x=520+Math.cos(a)*(255+wave)*Math.sin(p*Math.PI);const y=354+Math.sin(a)*(246+wave)*Math.sin(p*Math.PI)+Math.cos(p*Math.PI)*65;d+=`${k?'L':'M'}${f(x)},${f(y)}`;}
 paths+=`<path d="${d}" fill="none" stroke="rgb(${110+j},${155+j},255)" stroke-opacity="${f(.22+.65*Math.sin(p*Math.PI))}" stroke-width="1.25"/>`;
}
await writeFile(path.join(output,"chromatic.svg"),`<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="720" viewBox="0 0 1000 720"><defs><radialGradient id="g"><stop stop-color="#143cf2"/><stop offset=".65" stop-color="#0c1648"/><stop offset="1" stop-color="#070a10"/></radialGradient></defs><rect width="1000" height="720" fill="url(#g)"/>${paths}<g font-family="sans-serif"><text x="44" y="54" fill="#8daaff" font-size="15">EXPERIMENTS IN LIGHT</text><text x="39" y="649" fill="white" font-size="76" font-weight="bold">CHROMATIC</text><text x="44" y="685" fill="#8c9ed1" font-size="16">001 / FORM WITHOUT LIMITS</text></g></svg>`);
paths="";
for(let j=0;j<90;j++){let d="";for(let x=0;x<=1000;x+=6){const y=210+j*3+Math.sin(x*.006+j*.032)*110+Math.sin(x*.011-j*.09)*55;d+=`${x?'L':'M'}${x},${f(y)}`;}paths+=`<path d="${d}" fill="none" stroke="hsl(${205+j*.5},85%,${40+j*.4}%)" stroke-opacity=".8"/>`;}
await writeFile(path.join(output,"fluid.svg"),`<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="720" viewBox="0 0 1000 720"><rect width="1000" height="720" fill="#050709"/>${paths}<g font-family="sans-serif"><text x="50" y="565" fill="#e9f1ff" font-size="70" font-weight="600">Go with</text><text x="50" y="645" fill="#e9f1ff" font-size="70" font-weight="600">the flow.</text><text x="50" y="55" fill="#789dc6" font-size="14">FLUID SYSTEMS / 002</text></g></svg>`);
console.log('Generated static spatial artwork');
