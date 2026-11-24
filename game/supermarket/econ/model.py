import math
ND=11
speed=[28,19,8,6,3,1.2,.6,.5,.4,.32,.25]
inc1=[56*2.5**d for d in range(ND)]
base=[inc1[d]/speed[d] for d in range(ND)]
def nice(x):
    e=10**math.floor(math.log10(x)); m=x/e
    for c in (1,1.2,1.5,2,2.5,3,4,5,6,8,10):
        if m<=c*1.08: return c*e
    return 10*e
base=[nice(b) for b in base]; base[0]=2
upbase=[nice(base[d]*speed[d]*0.05*(1+d)) for d in range(ND)]; upbase[0]=2
build=[0,5e3,6e4,5e5,3e6,1.5e7,7e7,3e8,1.2e9,5e9,2e10]
RATE=1.045; STEP=0.08; ML=300
TL=[25,50,100,150,200,300]; TM=[1.5]*6
starC=[0,2e6,2e7,1.5e8,1e9,5e9,2e10,6e10,1.5e11,4e11,1e12,2.5e12,6e12,1.5e13,4e13,1e14]
starP=[1,1.5,2,2.5,3,4,5,6,7,8,10,12,14,16,18,20]
TB=[0,0.08,0.5,1.5,3,6,10,16,24,34,46]
TS=[0,1,2.5,5,8,12,17,23,30,38,47,57,68,80,95,110]
build=[0,5e3,1.5e5,1.2e6,6e6,3e7,1.5e8,8e8,3e9,1.2e10,5e10]
starC=[0,3e6,1.2e7,6e7,2.5e8,1e9,4e9,1.2e10,3e10,8e10,2e11,4e11,8e11,1.5e12,3e12,5e12]
def tierp(L): 
    m=1
    for l,k in zip(TL,TM):
        if L>=l: m*=k
    return m
lv=[1]+[0]*10; st=[1]+[0]*10; sp=[0]*ND; star=0
def price(d,L): return (base[d]+(L-1)*STEP*base[d])*tierp(L)
def dinc(d,L=None,S=None,P=None):
    L=lv[d] if L is None else L; S=st[d] if S is None else S; P=sp[d] if P is None else P
    if L==0: return 0
    return price(d,L)*speed[d]*(1+0.05*P)*S
def total(mult=None): return sum(dinc(d) for d in range(ND))*starP[star]*0.4
def hire(d,have): return (200 if d==0 else build[d]*0.5)*5**(have-1)
def prod(d,n): return upbase[d]*20*1.12**n
t=0;coin=1000;log=[]
while t<60*400:
    for d in range(1,ND):
        if build[d] is None and t>=TB[d]*60: build[d]=nice(20*total())
    for k in range(1,16):
        if starC[k] is None and t>=TS[k]*60: starC[k]=nice(30*total())
    inc=total(); best=None
    for d in range(ND):
        if lv[d]==0:
            if d>0 and lv[d-1]>0 and build[d] is not None:
                c=build[d]; g=dinc(d,1,1,0)*starP[star]*0.4*8  # value future growth
                best=min(best,(c/g,c,('build',d))) if best else (c/g,c,('build',d))
            continue
        cands=[]
        if lv[d]<ML: cands.append((upbase[d]*RATE**(lv[d]-1), (dinc(d,lv[d]+1)-dinc(d))*(3 if (lv[d]+1) in TL else 1), ('lv',d)))
        if st[d]<5: cands.append((hire(d,st[d]), dinc(d,S=st[d]+1)-dinc(d), ('hire',d)))
        if sp[d]<40: cands.append((prod(d,sp[d]), dinc(d,P=sp[d]+1)-dinc(d), ('prod',d)))
        for c,g,a in cands:
            g*=starP[star]*0.4
            if best is None or c/g<best[0]: best=(c/g,c,a)
    if star<15 and starC[star+1] is not None:
        c=starC[star+1]; g=inc*(starP[star+1]/starP[star]-1)
        if g>0 and (best is None or c/g<best[0]): best=(c/g,c,('star',0))
    if best is None or (best[1]>coin and (best[1]-coin)/inc>30):
        t+=10; coin+=10*inc; continue
    _,c,a=best
    if coin<c: t+=(c-coin)/inc; coin=c
    coin-=c
    k,d=a
    if k=='build': lv[d]=1;st[d]=1; log.append((t,'open %d'%d,inc))
    elif k=='lv': lv[d]+=1
    elif k=='hire': st[d]+=1
    elif k=='prod': sp[d]+=1
    else: star+=1; log.append((t,'star %d'%star,inc))
for x in log: print('%7.1f h  %-8s inc/min %.3g'%(x[0]/60,x[1],x[2]))
print('end',t/60,'h inc/min %.3g'%total(), lv, st, sp, star)
print('base',base);print('upbase',upbase)
print('build',build);print('starC',starC)
print('maxlevelcost',['%.3g'%(u*RATE**299) for u in upbase]); print('hire max',['%.3g'%hire(d,4) for d in range(ND)]); print('prod max',['%.3g'%prod(d,39) for d in range(ND)])
