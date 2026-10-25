// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

const assert = require('node:assert/strict')
const fs = require('node:fs')
const vm = require('node:vm')
let maps = 0
const context = vm.createContext({document: {createElement() {
    const canvas = {toDataURL: () => 'data:image/png;base64,fixture', getContext: () => ({
        createImageData: (w, h) => ({data: new Uint8ClampedArray(w * h * 4)}),
        putImageData(image) {
            ++maps
            assert.ok(canvas.width <= 512 && canvas.height <= 512)
            for (let i = 3; i < image.data.length; i += 4) assert.equal(image.data[i], 255)
        }
    })}
    return canvas
}}})
vm.runInContext(fs.readFileSync('src/FigmaTheme.js', 'utf8'), context)
vm.runInContext(context.liquidGlassSource, context)
const preset = context.normalizedLiquidGlass({})
assert.deepEqual(JSON.parse(JSON.stringify(preset)), {
    enabled:false, noiseStrength:0, brightness:100, saturation:180, contrast:100, cornerRadius:15,
    refractionStrength:100, refractionMode:'concave', refractionEdgeSize:30, refractionFalloff:400,
    refractionCornerRadius:15, rgbFringingStrength:0, innerShadowX:0, innerShadowY:2,
    innerShadowScale:12, innerShadowBrightness:100, innerShadowStrength:0, innerShadowColor:'#000000'
}, 'New liquid glass defaults match the requested preset')
const glass = {...preset, enabled:true, refractionMode:'basic', refractionFalloff:100, noiseStrength:3, rgbFringingStrength:2}
const vector = (x, y, settings = glass) => Array.from(context.glassDisplacement(x, y, 300, 400, settings))
assert.deepEqual(vector(150, 200), [0, 0], 'The center remains undistorted')
assert.ok(vector(1, 200)[0] < 0 && vector(299, 200)[0] > 0, 'Opposite edges bend in opposite directions')
assert.equal(vector(1, 200)[1], 0, 'Straight edges do not bend along their tangent')
const basic = vector(4, 4), concave = vector(4, 4, {...glass, refractionMode: 'concave'})
assert.ok(basic.every((value, i) => value === -concave[i]), 'Concave reverses the lens direction')
assert.ok(vector(4, 4, {...glass, refractionCornerRadius: 0})[0] === 0, 'Refraction radius changes corner normals')
assert.ok(Math.abs(vector(20, 200, {...glass, refractionEdgeSize: 100})[0]) > Math.abs(vector(20, 200)[0]))
assert.ok(Math.abs(vector(20, 200, {...glass, refractionFalloff: 200})[0]) < Math.abs(vector(20, 200)[0]))
for (const size of [[1, 1], [48, 1000], [1200, 60]]) {
    for (let y = 0; y <= size[1]; y += size[1] / 4)
        for (let x = 0; x <= size[0]; x += size[0] / 4)
            assert.ok(Array.from(context.glassDisplacement(x, y, ...size, glass)).every(n => Number.isFinite(n) && Math.abs(n) <= 1))
}
const clamped = context.normalizedLiquidGlass({noiseStrength: Infinity, brightness: -4, contrast: 999,
    refractionEdgeSize: 0, refractionMode: '<invalid>', refractionFalloff: NaN})
assert.equal(clamped.noiseStrength, 0)
assert.equal(clamped.brightness, 0)
assert.equal(clamped.contrast, 200)
assert.equal(clamped.refractionEdgeSize, 1)
assert.equal(clamped.refractionMode, 'concave')
assert.equal(clamped.refractionFalloff, 400)
const shadow = context.normalizedLiquidGlass({innerShadowX:-8, innerShadowY:6, innerShadowScale:24,
    innerShadowBrightness:150, innerShadowStrength:40, innerShadowColor:'#80c020'})
assert.equal(context.glassInnerShadow(shadow), 'inset -8px 6px 24px 0 rgba(192,255,48,0.4)',
    'Inner shadow uses independent position, scale, brightness, strength and color')
assert.equal(context.glassInnerShadow({...shadow, innerShadowStrength:0}), '0 0 transparent')
const invalidShadow = context.normalizedLiquidGlass({innerShadowX:-999, innerShadowY:999, innerShadowScale:-20,
    innerShadowBrightness:999, innerShadowStrength:NaN, innerShadowColor:'red;filter:blur(50px)'})
assert.equal(invalidShadow.innerShadowX, -100)
assert.equal(invalidShadow.innerShadowY, 100)
assert.equal(invalidShadow.innerShadowScale, 0)
assert.equal(invalidShadow.innerShadowBrightness, 200)
assert.equal(invalidShadow.innerShadowStrength, 0)
assert.equal(invalidShadow.innerShadowColor, '#000000')
const svg = context.glassFilter(300, 900, glass, 'glass-test')
assert.match(svg, /feDisplacementMap/)
assert.match(svg, /result="red"/)
assert.match(svg, /result="green"/)
assert.match(svg, /result="blue"/)
assert.match(svg, /feTurbulence/)
assert.equal(maps, 1)
const neutral = context.glassFilter(300, 900, {...glass, noiseStrength: 0, refractionStrength: 0, rgbFringingStrength: 0}, 'neutral')
assert.doesNotMatch(neutral, /feDisplacementMap|feTurbulence|feImage/)
assert.equal(maps, 1, 'Zero refraction and fringing skip displacement texture generation')
console.log('Liquid glass geometry, limits and filter checks passed')
