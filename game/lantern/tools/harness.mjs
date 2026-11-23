// Loads the game's rule code (core + solver) outside a browser, for tools and tests.
import fs from "node:fs";import path from "node:path";import {fileURLToPath} from "node:url";
const dir=path.dirname(fileURLToPath(import.meta.url));
export function load(extra=""){const src=["core.js","solver.js"].map(f=>fs.readFileSync(path.join(dir,"../prototype3d",f),"utf8")).join("\n");
const stub=`const document={getElementById:()=>({}),createElement:()=>({getContext:()=>({})}),body:{appendChild(){}},documentElement:{},addEventListener(){}};const localStorage={getItem:()=>null,setItem(){}};
const matchMedia=()=>({matches:false});class Audio{canPlayType(){return ""}addEventListener(){}};class Image{};const navigator={};const window={};const addEventListener=()=>{};const S={sound:false,lang:"en"};`;
return new Function(stub+src+extra+";return {rng,perm,grow,countSolutions,solveSteps,levelSpec,levelPuzzle,dailyPuzzle,gradedPuzzle}")()}
