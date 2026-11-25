/* 貓躲狗找 — renderer + own post chain: HDR scene -> SSAO -> dual-filter bloom -> ACES grade/vignette/grain. */
(function () {
  'use strict';
  var SG = (window.SG = window.SG || {});

  var VS = 'in vec3 position; in vec2 uv; out vec2 vUv; void main(){ vUv=uv; gl_Position=vec4(position.xy,0.,1.); }';
  function pass(fs, uniforms) {
    return new THREE.RawShaderMaterial({
      glslVersion: THREE.GLSL3, vertexShader: VS, depthTest: false, depthWrite: false, uniforms: uniforms,
      fragmentShader: 'precision highp float; precision highp sampler2D; in vec2 vUv; out vec4 o;\n' + fs
    });
  }

  var FS_SSAO = [
    'uniform sampler2D tDepth; uniform mat4 uProj, uInvProj; uniform vec2 uRes; uniform float uRadius;',
    'vec3 vp(vec2 uv){ float d=texture(tDepth,uv).x; vec4 c=uInvProj*vec4(uv*2.-1.,d*2.-1.,1.); return c.xyz/c.w; }',
    'float hash(vec2 p){ return fract(52.9829189*fract(dot(p,vec2(0.06711056,0.00583715)))); }',
    'void main(){',
    '  float d0=texture(tDepth,vUv).x; if(d0>=0.9999){ o=vec4(1.); return; }',
    '  vec3 p=vp(vUv); vec2 px=1./uRes;',
    '  vec3 pr=vp(vUv+vec2(px.x,0.)), pl=vp(vUv-vec2(px.x,0.)), pu=vp(vUv+vec2(0.,px.y)), pd=vp(vUv-vec2(0.,px.y));',
    '  vec3 dx=abs(pr.z-p.z)<abs(p.z-pl.z)?pr-p:p-pl; vec3 dy=abs(pu.z-p.z)<abs(p.z-pd.z)?pu-p:p-pd;',
    '  vec3 n=normalize(cross(dx,dy));',
    '  float rnd=hash(gl_FragCoord.xy)*6.2831853, occ=0.;',
    '  const int N=12;',
    '  for(int i=0;i<N;i++){',
    '    float fi=float(i)+0.5; float a=rnd+fi*2.39996; float z=fi/float(N); float rr=sqrt(1.-z*z);',
    '    vec3 dir=vec3(cos(a)*rr,sin(a)*rr,z);',
    '    vec3 t=normalize(abs(n.y)<0.9?cross(n,vec3(0.,1.,0.)):cross(n,vec3(1.,0.,0.))); vec3 b=cross(n,t);',
    '    vec3 sp=p+(t*dir.x+b*dir.y+n*dir.z)*uRadius*(0.25+0.75*hash(gl_FragCoord.xy+fi*7.));',
    '    vec4 c=uProj*vec4(sp,1.); vec2 suv=c.xy/c.w*0.5+0.5;',
    '    float sz=vp(suv).z;',
    '    float rc=smoothstep(0.,1.,uRadius/max(abs(p.z-sz),1e-4));',
    '    occ+=step(sp.z+0.012,sz)*rc;',
    '  }',
    '  o=vec4(vec3(1.-occ/float(N)),1.);',
    '}'].join('\n');

  var FS_DOWN = [
    'uniform sampler2D tSrc; uniform vec2 uPx; uniform float uThresh;',
    'vec3 pre(vec3 c){ if(uThresh<=0.) return c; float l=max(c.r,max(c.g,c.b)); float k=max(l-uThresh,0.); k=k*k/(k+0.6); return c*k/max(l,1e-4); }',
    'void main(){',
    '  vec3 a=pre(texture(tSrc,vUv).rgb)*4.;',
    '  a+=pre(texture(tSrc,vUv+uPx*vec2(-1.,-1.)).rgb)+pre(texture(tSrc,vUv+uPx*vec2(1.,-1.)).rgb)+pre(texture(tSrc,vUv+uPx*vec2(-1.,1.)).rgb)+pre(texture(tSrc,vUv+uPx*vec2(1.,1.)).rgb);',
    '  o=vec4(min(a/8.,vec3(40.)),1.);',
    '}'].join('\n');
  var FS_UP = [
    'uniform sampler2D tSrc, tAdd; uniform vec2 uPx;',
    'void main(){',
    '  vec3 a=texture(tSrc,vUv+uPx*vec2(-1.,0.)).rgb+texture(tSrc,vUv+uPx*vec2(1.,0.)).rgb+texture(tSrc,vUv+uPx*vec2(0.,-1.)).rgb+texture(tSrc,vUv+uPx*vec2(0.,1.)).rgb;',
    '  a+=(texture(tSrc,vUv+uPx*vec2(-.7,-.7)).rgb+texture(tSrc,vUv+uPx*vec2(.7,-.7)).rgb+texture(tSrc,vUv+uPx*vec2(-.7,.7)).rgb+texture(tSrc,vUv+uPx*vec2(.7,.7)).rgb);',
    '  o=vec4(a/8.+texture(tAdd,vUv).rgb,1.);',
    '}'].join('\n');

  var FS_FINAL = [
    'uniform sampler2D tScene, tBloom, tAO; uniform vec2 uAOPx; uniform float uBloom, uExposure, uTime, uVignette, uAO, uSat, uFade, uMono, uHorror, uMosaic; uniform vec3 uTint;',
    'vec3 aces(vec3 x){ return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14),0.,1.); }',
    'float hash(vec2 p){ return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453); }',
    'void main(){',
    '  vec2 suv=vUv; if(uMosaic>0.5){ vec2 g=vec2(textureSize(tScene,0))/uMosaic; suv=(floor(vUv*g)+0.5)/g; }', // host filter: mosaic
    '  vec3 c=texture(tScene,suv).rgb;',
    '  float ao=0.; for(int y=-1;y<=2;y++) for(int x=-1;x<=2;x++) ao+=texture(tAO,vUv+(vec2(float(x),float(y))-0.5)*uAOPx).r; ao/=16.;',
    '  ao=mix(1.,ao,uAO); c*=mix(vec3(0.42,0.30,0.24),vec3(1.),ao);', // warm-tinted occlusion, never pure black
    '  c+=texture(tBloom,vUv).rgb*uBloom;',
    '  c*=uExposure; c=aces(c);',
    '  float l=dot(c,vec3(0.2126,0.7152,0.0722));',
    '  c=mix(vec3(l),c,uSat);',
    '  c=mix(c,c*uTint,0.5); c+=vec3(0.012,0.006,0.0)*(1.-l);', // warm toe
    '  c=c*c*(3.-2.*c)*0.35+c*0.65;', // gentle S curve
    '  vec2 q=vUv-0.5; float v=smoothstep(0.85,0.2,dot(q,q)*1.9); c*=mix(1.-uVignette,1.,v);',
    '  if(uMono>0.5) c=vec3(dot(c,vec3(0.3,0.59,0.11)));', // host filter: monochrome
    '  if(uHorror>0.5){ c*=vec3(0.30,0.33,0.42); c*=smoothstep(0.62,0.04,dot(q,q)*2.4); }', // host filter: dark, narrow view
    '  c=pow(c,vec3(1./2.2));',
    '  c+=(hash(gl_FragCoord.xy+uTime)-0.5)/200.;',
    '  o=vec4(c*uFade,1.);',
    '}'].join('\n');

  SG.Post = function (canvas, opt) {
    opt = opt || {};
    var low = opt.low;
    var R = new THREE.WebGLRenderer({ canvas: canvas, antialias: false, alpha: false, powerPreference: 'high-performance', preserveDrawingBuffer: true });
    R.shadowMap.enabled = true; R.shadowMap.type = THREE.PCFShadowMap;
    R.toneMapping = THREE.NoToneMapping;
    R.info.autoReset = false;
    this.renderer = R;
    var gl = R.getContext();
    var hf = !!gl.getExtension('EXT_color_buffer_float') || !!gl.getExtension('EXT_color_buffer_half_float');
    var type = hf ? THREE.HalfFloatType : THREE.UnsignedByteType;
    var quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2));
    quad.frustumCulled = false;
    var qscene = new THREE.Scene(); qscene.add(quad);
    var qcam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    var rtScene, rtAO, mips = [], W = 0, H = 0;
    var mSSAO = pass(FS_SSAO, { tDepth: { value: null }, uProj: { value: new THREE.Matrix4() }, uInvProj: { value: new THREE.Matrix4() }, uRes: { value: new THREE.Vector2() }, uRadius: { value: 0.32 } });
    var mDown = pass(FS_DOWN, { tSrc: { value: null }, uPx: { value: new THREE.Vector2() }, uThresh: { value: 0 } });
    var mUp = pass(FS_UP, { tSrc: { value: null }, tAdd: { value: null }, uPx: { value: new THREE.Vector2() } });
    var mFinal = pass(FS_FINAL, {
      tScene: { value: null }, tBloom: { value: null }, tAO: { value: null }, uAOPx: { value: new THREE.Vector2() },
      uBloom: { value: 0.5 }, uExposure: { value: 0.92 }, uTime: { value: 0 }, uVignette: { value: 0.38 }, uAO: { value: 1.0 },
      uSat: { value: 1.04 }, uFade: { value: 1 }, uMono: { value: 0 }, uHorror: { value: 0 }, uMosaic: { value: 0 }, uTint: { value: new THREE.Vector3(1.02, 1.0, 0.97) }
    });
    this.final = mFinal.uniforms;
    this.ssao = mSSAO.uniforms;
    var NM = 5;
    function rt(w, h, o) {
      return new THREE.WebGLRenderTarget(Math.max(1, w), Math.max(1, h), Object.assign({ type: type, minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter, depthBuffer: false }, o || {}));
    }
    this.setSize = function (w, h, dpr) {
      dpr = dpr || 1;
      R.setPixelRatio(1); R.setSize(w, h, false);
      W = Math.round(w * dpr); H = Math.round(h * dpr);
      R.setSize(W, H, false);
      if (rtScene) { rtScene.dispose(); rtAO.dispose(); mips.forEach(function (m) { m.d.dispose(); m.u.dispose(); }); }
      var dt = new THREE.DepthTexture(W, H); dt.type = THREE.UnsignedIntType;
      rtScene = rt(W, H, { depthBuffer: true, depthTexture: dt, samples: low ? 0 : 4 });
      rtAO = new THREE.WebGLRenderTarget(W >> 1, H >> 1, { type: THREE.UnsignedByteType, minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter, depthBuffer: false });
      mips = [];
      for (var i = 0; i < NM; i++) mips.push({ d: rt(W >> (i + 1), H >> (i + 1)), u: rt(W >> (i + 1), H >> (i + 1)) });
      this.width = W; this.height = H;
    };
    function draw(mat, target) { quad.material = mat; R.setRenderTarget(target); R.render(qscene, qcam); }
    this.render = function (scene, camera, time) {
      R.info.reset(); R.setRenderTarget(rtScene); R.render(scene, camera);
      this.sceneCalls = R.info.render.calls; this.sceneTris = R.info.render.triangles;
      // SSAO
      if (!low) {
        mSSAO.uniforms.tDepth.value = rtScene.depthTexture;
        mSSAO.uniforms.uProj.value.copy(camera.projectionMatrix);
        mSSAO.uniforms.uInvProj.value.copy(camera.projectionMatrixInverse);
        mSSAO.uniforms.uRes.value.set(rtAO.width, rtAO.height);
        draw(mSSAO, rtAO);
      }
      // bloom: down chain with prefilter on the first step, then tent up-sampling
      var src = rtScene.texture, i;
      for (i = 0; i < NM; i++) {
        mDown.uniforms.tSrc.value = src; mDown.uniforms.uThresh.value = i === 0 ? 1.5 : 0;
        mDown.uniforms.uPx.value.set(1 / mips[i].d.width, 1 / mips[i].d.height);
        draw(mDown, mips[i].d); src = mips[i].d.texture;
      }
      var up = mips[NM - 1].d.texture;
      for (i = NM - 2; i >= 0; i--) {
        mUp.uniforms.tSrc.value = up; mUp.uniforms.tAdd.value = mips[i].d.texture;
        mUp.uniforms.uPx.value.set(1 / mips[i + 1].d.width, 1 / mips[i + 1].d.height);
        draw(mUp, mips[i].u); up = mips[i].u.texture;
      }
      var u = mFinal.uniforms;
      u.tScene.value = rtScene.texture; u.tBloom.value = up; u.tAO.value = rtAO.texture;
      u.uAOPx.value.set(1 / rtAO.width, 1 / rtAO.height); u.uTime.value = (time || 0) % 10;
      if (low) u.uAO.value = 0;
      draw(mFinal, null);
    };

    /* ---- albedo-only renders (eyedropper, auto-camouflage, dog vision). Layer 0 = world, 1 = fx + real lights, 2 = flat light ---- */
    var rtPick = new THREE.WebGLRenderTarget(1, 1, { type: THREE.UnsignedByteType });
    var flat = new THREE.AmbientLight(0xffffff, Math.PI); flat.layers.set(2);
    this.flatLight = flat;
    function lin2srgb(v) { v /= 255; return Math.round(255 * (v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow(v, 1 / 2.4) - 0.055)); }
    this.renderAlbedo = function (scene, camera, w, h, out, mode) { // mode: undefined = unlit albedo (sRGB bytes), 'raw' = unlit, linear bytes, 'lit' = with the real lights, before any grading
      if (rtPick.width !== w || rtPick.height !== h) rtPick.setSize(w, h);
      var env = scene.environment, bg = scene.background, mask = camera.layers.mask, lit = mode === 'lit';
      if (!lit) { scene.environment = null; camera.layers.mask = 1 | 4; }
      var sh = R.shadowMap.autoUpdate; R.shadowMap.autoUpdate = false;
      R.setRenderTarget(rtPick); R.setClearColor(0x808080, 1); R.clear(); R.render(scene, camera);
      out = out || new Uint8Array(w * h * 4);
      R.readRenderTargetPixels(rtPick, 0, 0, w, h, out);
      R.setRenderTarget(null);
      scene.environment = env; scene.background = bg; camera.layers.mask = mask; R.shadowMap.autoUpdate = sh;
      if (mode !== 'raw') for (var i = 0; i < out.length; i += 4) { out[i] = lin2srgb(out[i]); out[i + 1] = lin2srgb(out[i + 1]); out[i + 2] = lin2srgb(out[i + 2]); }
      return out;
    };
    var pickCam = new THREE.PerspectiveCamera(), px = new Uint8Array(4);
    this.pick = function (scene, camera, nx, ny, viewW, viewH, mode) { // colour under a screen pixel: 'lit' (as rendered, before grading) or unlit surface colour
      pickCam.copy(camera); pickCam.setViewOffset(viewW, viewH, Math.floor(nx), Math.floor(ny), 1, 1); pickCam.updateProjectionMatrix();
      pickCam.matrixWorld.copy(camera.matrixWorld); pickCam.matrixWorldInverse.copy(camera.matrixWorldInverse);
      pickCam.layers.mask = camera.layers.mask; this.renderAlbedo(scene, pickCam, 1, 1, px, mode === 'lit' ? 'lit' : undefined);
      return [px[0], px[1], px[2]];
    };
  };
})();
