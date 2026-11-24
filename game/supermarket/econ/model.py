# Fast mirror of the 1000-level economy (same formulas as Souq.Core.Sim / Tables.cs after the 2026-11-23 rewrite).
# Used only to tune numbers quickly; the cloud audit (Editor/EconAudit.cs) runs the real C# and is the authority.
import math, random, json, sys
ND=11
def nice(x):
    if x<=0: return 0
    e=10**math.floor(math.log10(x)); m=x/e
    for c in (1,1.2,1.5,2,2.5,3,4,5,6,8,10):
        if m<=c*1.1: return float('%.3g'%(c*e))
    return 10*e
class T: pass
t=T()
t.MaxLevel=1000; t.Step=0.05; t.PriceGeo=1.007; t.MileEvery=50; t.MileMul=1.3;
t.Base=[2,9,40,180,800,3.5e3,1.5e4,6.5e4,2.8e5,1.2e6,5e6]
t.UpBase=[b*0.6 for b in t.Base]
t.Ceil=1e18; t.UpRate=[(t.Ceil/u)**(1/999) for u in t.UpBase]
t.Visit=[95,80,70,65,55,50,45,40,35,30,25]
t.Speed=[3.6,3.0,2.6,2.4,2.1,1.9,1.7,1.5,1.3,1.1,0.94]
t.SpeedMax=50; t.SpeedStep=0.04; t.SpeedCostMul=10; t.SpeedCostRate=1.15
t.HireRate=3; t.HireFrac=0.3; t.HireMin=50
t.Build=[0,300,4e3,4e4,4e5,4e6,4e7,4e8,4e9,4e10,4e11]
t.AdBase=20; t.AdRate=1.33; t.AdMax=40; t.CarsBase=6; t.CarsStep=1.5
t.ParkPer=6; t.ParkCost=[nice(60*2.6**i) for i in range(14)]; t.Stay=1.3
t.CashOpen=[0,200,2e3,2e4,3e5,5e6,1e8,2e9]; t.CashBase=[7,4,4,4.5,4.5,5,5,5.5]; t.CashStep=0.1; t.CashMax=40
t.CashUpBase=[10,10,25,60,150,400,1e3,2.5e3]; t.CashUpRate=1.25
t.StarProfit=[1,1.5,2,2.6,3.3,4.1,5,6,7.2,8.5,10,12,14,16.5,19,22]
t.StarCost=[0]+[1e6*8**i for i in range(15)]
t.Offline=120; t.Session=90; t.TruckEvery=50/60
def fmt(x):
    if x<1000: return '%.3g'%x
    u=['K','M','B','T','Qa','Qi','Sx','Sp','Oc','No','Dc']; e=int(math.log10(x)//3)
    return ('%.3g'%(x/1000**e))+u[e-1] if e-1<len(u) else '%.2e'%x
class Sim:
    def __init__(s,t):
        s.t=t; s.lv=[1]*ND; s.op=[True]+[False]*(ND-1); s.st=[1]*ND; s.sp=[0]*ND; s.cl=[1]+[0]*7
        s.park=1; s.ad=1; s.star=0; s.coin=1000.0; s.profitEpic=0; s.mgr=[0]*ND; s.res=[0]*ND
    def mult(s): return s.t.StarProfit[s.star]*(1+0.2*s.profitEpic)
    def price(s,d): L=s.lv[d]; return s.t.Base[d]*s.t.PriceGeo**(L-1)*s.t.MileMul**(L//s.t.MileEvery)*s.mult()
    def staffSpeed(s,d): return s.t.Speed[d]*(1+s.t.SpeedStep*s.sp[d])*(1+0.5*s.mgr[d])
    def arrivals(s): return min(s.t.CarsBase+s.t.CarsStep*(s.ad-1), s.t.ParkPer*s.park/s.t.Stay)
    def cash(s): return sum(s.t.CashBase[c]+(s.cl[c]-1)*s.t.CashStep for c in range(8) if s.cl[c]>0)
    def flow(s):
        a=s.arrivals(); sc=min(1,s.cash()/a); e=0
        for d in range(ND):
            if s.op[d]: e+=s.price(d)*min(s.staffSpeed(d)*s.st[d], a*s.t.Visit[d]/100)*sc
        return e
    # costs (inf when maxed)
    def levelCost(s,d): return math.inf if s.lv[d]>=s.t.MaxLevel else s.t.UpBase[d]*s.t.UpRate[d]**(s.lv[d]-1)*(1-0.03*s.res[d])
    def hireCost(s,d): return math.inf if s.st[d]>=5 else max(s.t.HireMin,s.t.Build[d]*s.t.HireFrac)*s.t.HireRate**(s.st[d]-1)
    def speedCost(s,d): return math.inf if s.sp[d]>=s.t.SpeedMax else s.t.UpBase[d]*s.t.SpeedCostMul*s.t.SpeedCostRate**s.sp[d]
    def adCost(s): return math.inf if s.ad>=s.t.AdMax else s.t.AdBase*s.t.AdRate**(s.ad-1)
    def parkCost(s): return math.inf if s.park>len(s.t.ParkCost) else s.t.ParkCost[s.park-1]
    def cashOpenCost(s):
        n=sum(1 for c in s.cl if c>0); return math.inf if n>=8 else s.t.CashOpen[n]
    def cashUpCost(s,c): return math.inf if s.cl[c]<=0 or s.cl[c]>=s.t.CashMax else s.t.CashUpBase[c]*s.t.CashUpRate**(s.cl[c]-1)
    def options(s):
        o=[]
        nx=next((d for d in range(ND) if not s.op[d]),-1)
        if nx>=0: o.append(('build',nx,s.t.Build[nx]))
        if s.star+1<len(s.t.StarCost): o.append(('star',0,s.t.StarCost[s.star+1]))
        for d in range(ND):
            if s.op[d]: o+= [('lv',d,s.levelCost(d)),('hire',d,s.hireCost(d)),('speed',d,s.speedCost(d))]
        o+=[('ad',0,s.adCost()),('park',0,s.parkCost()),('copen',0,s.cashOpenCost())]
        for c in range(8): o.append(('cup',c,s.cashUpCost(c)))
        return [x for x in o if x[2]<math.inf]
    def apply(s,k,i,sign=1):
        if k=='build': s.op[i]= sign>0
        elif k=='star': s.star+=sign
        elif k=='lv': s.lv[i]+=sign
        elif k=='hire': s.st[i]+=sign
        elif k=='speed': s.sp[i]+=sign
        elif k=='ad': s.ad+=sign
        elif k=='park': s.park+=sign
        elif k=='copen':
            if sign>0: s.cl[s.cl.index(0)]=1
            else: j=max(c for c in range(8) if s.cl[c]>0); s.cl[j]=0
        elif k=='cup': s.cl[i]+=sign
    def gain(s,k,i):
        f0=s.flow(); s.apply(k,i,1); f1=s.flow(); s.apply(k,i,-1); return f1-f0
def play(t,days=21,style='best',trace=None):
    s=Sim(t); tm=0.0; ev=[]; stats=dict(maxGap=0,useless={},paybacks=[],jumps=0,maxNum=0,idle=0)
    lastBuy=0.0; dt=0.5; flows=[]
    def bundle(f,commit=False):
        # one more advert level, plus the car park and checkout room it needs to pay off
        done=[]; c=s.adCost(); s.apply('ad',0); done.append(('ad',0))
        for _ in range(30):
            a=s.t.CarsBase+s.t.CarsStep*(s.ad-1)
            if s.t.ParkPer*s.park/s.t.Stay < a and s.parkCost()<math.inf: c+=s.parkCost(); s.apply('park',0); done.append(('park',0)); continue
            if s.cash() < s.arrivals():
                n=sum(1 for x in s.cl if x>0); opts=[(s.cashUpCost(j),'cup',j) for j in range(8) if s.cl[j]>0]+[(s.cashOpenCost(),'copen',0)]
                cc,k,j=min(opts)
                if cc<math.inf: c+=cc; s.apply(k,j); done.append((k,j)); continue
            break
        g=s.flow()-f
        if not commit:
            for k,j in reversed(done): s.apply(k,j,-1)
        return g,c,done
    def pick():
        ops=s.options(); f=s.flow()
        # parking and adverts only pay together once the car park is full: offer the pair
        ops=[x for x in ops if x[0]!='ad']
        if s.adCost()<math.inf: ops.append(('adpark',0,0))
        best=None; afford=None
        for k,i,c in ops:
            if k=='adpark':
                g,c,_=bundle(f)
            else: g=s.gain(k,i)
            if k=='build': g=max(g, s.t.Base[i]*s.mult()*0.5)
            if g<=0: continue
            pb=c/g
            if best is None or pb<best[0]: best=(pb,k,i,c)
            if c<=s.coin and (afford is None or pb<afford[0]): afford=(pb,k,i,c)
        if style=='cheap':
            ok=[x for x in ops if x[2]<=s.coin]
            if not ok: return None
            k,i,c=min(ok,key=lambda x:x[2]); return (0,k,i,c)
        if afford is None: return None
        if best[3]<=s.coin: return best
        wait=(best[3]-s.coin)/max(f,1e-9)
        return afford if afford[0]<=max(30,wait) else None
    def buy():
        nonlocal lastBuy
        n=0
        for _ in range(600):
            p=pick()
            if p is None: break
            pb,k,i,c=p; f=s.flow()
            if k=='adpark':
                g,c,_=bundle(f)
                if c>s.coin: break
                bundle(f,True); s.coin-=c
            else:
                g=s.gain(k,i)
                if g<=0 and k in('lv','hire','speed'): stats['useless'][k]=stats['useless'].get(k,0)+1
                s.coin-=c; s.apply(k,i,1)
            stats['paybacks'].append(pb); n+=1
            stats['maxNum']=max(stats['maxNum'],c)
            if f>0 and s.flow()/f>3 and k!='build': stats['jumps']+=1
            if k=='build': ev.append(('build%d'%i,tm,s.flow()))
            if k=='star': ev.append(('star%d'%s.star,tm,s.flow()))
        if n: lastBuy=tm
    for day in range(days):
        t0=tm
        while tm<t0+t.Session-1e-9:
            f=s.flow(); s.coin+=f*dt*(1+0.35/t.TruckEvery); tm+=dt     # delivery trucks tapped while playing
            if int(tm)!=int(tm-dt): flows.append((tm,f,day))
            buy()
            if int(tm)!=int(tm-dt):
                f=s.flow(); best=math.inf; cheapest=math.inf
                for k,i,c in s.options():
                    if k=='ad': continue
                    g=s.gain(k,i)
                    if k=='build': g=max(g,s.t.Base[i]*s.mult()*0.5)
                    if g>0: best=min(best,c/g); cheapest=min(cheapest,c)
                if s.adCost()<math.inf:
                    g,c,_=bundle(f)
                    if g>0: best=min(best,c/g); cheapest=min(cheapest,c)
                stats.setdefault('best',[]).append(best)
                wait=max(0,(cheapest-s.coin)/max(f,1e-9))
                if day<10: stats['maxGap']=max(stats['maxGap'],wait)
            stats['maxNum']=max(stats['maxNum'],s.coin)
        if s.park>1: s.coin+=s.flow()*t.Offline
        lastBuy=tm
    hr=[]; sess={}
    for k in range(len(flows)):
        a,f,dd=flows[k]
        sess.setdefault(dd,[f,f]); sess[dd][1]=f
        if a>=120 and k>=60 and flows[k-60][2]==dd and flows[k-60][1]>0: hr.append(f/flows[k-60][1])
    stats['hourGrowth']=max(hr) if hr else 0
    stats['session']=[v[1]/v[0] for dd,v in sorted(sess.items())]
    return s,ev,stats,flows
def flowAt(flows,tm):
    for a,f,_ in flows:
        if a>=tm: return f
    return flows[-1][1]
def tune(t,rounds=14,days=21,damp=0.4,quiet=False):
    S=t.Session
    tb=[0,5,15,40,1*S+20,2*S+20,3*S+40,5*S+20,7*S+40,10*S+20,14*S+20]
    ts=[0]+[x*S for x in (0.4,1,1.6,2.4,3.3,4.3,5.5,7,8.5,10.5,12.5,14.5,17,19.5,22)]
    tl=[700,680,650,620,580,540,480,420,350,280,200]
    for r in range(rounds):
        s,ev,st,flows=play(t,days+3)
        got={e[0]:e[1] for e in ev}; err=0
        for d in range(1,ND):
            a=got.get('build%d'%d,(days+3)*S); err+=abs(math.log((a+5)/(tb[d]+5)))
            t.Build[d]*=max(0.1,min(10,flowAt(flows,tb[d])/flowAt(flows,a)))**damp
        for k in range(1,16):
            a=got.get('star%d'%k,(days+3)*S); err+=abs(math.log((a+5)/(ts[k]+5)))
            t.StarCost[k]*=max(0.1,min(10,flowAt(flows,ts[k])/flowAt(flows,a)))**damp
        for d in range(2,ND): t.Build[d]=max(t.Build[d],t.Build[d-1]*2)
        for k in range(2,16): t.StarCost[k]=max(t.StarCost[k],t.StarCost[k-1]*1.4)
        if not quiet: print('round',r,'error %.2f'%err, flush=True)
    t.Build=[nice(x) for x in t.Build]; t.StarCost=[nice(x) for x in t.StarCost]; t.UpRate=[round(x,5) for x in t.UpRate]
    return err
def report(t,style='best',days=21):
    s,ev,st,flows=play(t,days,style)
    S=t.Session
    for e in ev: print('%-7s day %2d +%4.0f min   flow/min %s'%(e[0],int(e[1]//S)+1,e[1]%S,fmt(e[2])))
    print('end lv',s.lv,'staff',s.st,'speed',s.sp,'ad',s.ad,'park',s.park,'cash',s.cl,'star',s.star,'flow',fmt(s.flow()),'coin',fmt(s.coin))
    bb=sorted(st['best']); print('best payback while playing: median %.1f p90 %.1f max %.1f min'%(bb[len(bb)//2],bb[int(len(bb)*.9)],bb[-1]),'| worst active-hour growth x%.1f'%st['hourGrowth'])
    print('income growth inside each day\'s session:', ' '.join('x%.2g'%x for x in st['session']))
    pb=sorted(st['paybacks']) or [0]; print('payback median %.1f p90 %.1f max %.1f'%(pb[len(pb)//2],pb[int(len(pb)*.9)],pb[-1]),'longest wait for anything useful (first 10 days) %.1f min'%st['maxGap'],'useless',st['useless'],'jumps',st['jumps'],'maxNum',fmt(st['maxNum']))
    return s,ev,st
if __name__=='__main__':
    if 'tune' in sys.argv:
        tune(t); print('Build',t.Build); print('StarCost',t.StarCost); print('UpRate',t.UpRate)
        json.dump(dict(Build=t.Build,StarCost=t.StarCost,UpRate=t.UpRate),open('tuned.json','w'))
    report(t)
