// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
let documentListeners={},windowListeners={},messages=[],microtasks=[];
class Element {
 constructor({cursor='auto',input=null,parent=null,value='',type='text',inputMode=''}={}){Object.assign(this,{cursor,input,parentElement:parent,value,type,inputMode})}
 matches(){return this.input===this}
 querySelector(){return this.input}
}
const context={Element,location:{protocol:'https:',hostname:'www.figma.com'},getComputedStyle:n=>({cursor:n.cursor}),
 document:{addEventListener:(name,fn)=>documentListeners[name]=fn},window:{addEventListener:(name,fn)=>windowListeners[name]=fn},
 queueMicrotask:fn=>microtasks.push(fn),__resketchNative:(...args)=>messages.push(args)};
vm.createContext(context);vm.runInContext(fs.readFileSync('src/FigmaScrub.js','utf8'),context);
const press=(target,extra={})=>documentListeners.pointerdown({target,isTrusted:true,isPrimary:true,button:0,pointerId:1,clientX:10,clientY:10,...extra});
const flush=()=>{for(const fn of microtasks.splice(0))fn()};
const input=new Element({value:'15',cursor:'ew-resize'});input.input=input;const wrapper=new Element({cursor:'ew-resize',input});input.parentElement=wrapper;
const move=()=>documentListeners.pointermove({isTrusted:true,pointerId:1,buttons:1,clientX:20,clientY:10});
press(input);flush();assert.equal(messages.length,0,'A click alone never captures');move();assert.equal(messages.length,0);flush();assert.deepEqual(messages.pop(),['numeric-scrub','start']);
documentListeners.pointerup();assert.deepEqual(messages.pop(),['numeric-scrub','stop']);documentListeners.pointerup();assert.equal(messages.length,0);
press(new Element({cursor:'col-resize'}));move();flush();assert.equal(messages.length,0,'Sidebar resize cannot capture');
press(new Element({value:'A title'}));move();flush();assert.equal(messages.length,0,'Text fields cannot capture');
press(input,{isTrusted:false});press(input,{button:2});move();flush();assert.equal(messages.length,0);
for(const stop of [()=>documentListeners.pointercancel(),()=>documentListeners.keydown({key:'Escape'}),()=>windowListeners.blur(),()=>{context.document.hidden=true;documentListeners.visibilitychange()}]){
 press(input);move();flush();assert.deepEqual(messages.pop(),['numeric-scrub','start']);stop();assert.deepEqual(messages.pop(),['numeric-scrub','stop']);
}
press(input);move();documentListeners.pointerup();messages=[];flush();assert.equal(messages.length,0,'No late capture after release');
const editing=new Element({value:'15',cursor:'text',parent:wrapper});editing.input=editing;press(editing);move();flush();assert.equal(messages.length,0,'Numeric text editing retains normal selection');
context.location.hostname='example.com';documentListeners={};vm.runInContext(fs.readFileSync('src/FigmaScrub.js','utf8'),context);assert.deepEqual(documentListeners,{});
console.log('Numeric scrub detection, delayed capture, nonnumeric controls, origins and all release paths passed');
