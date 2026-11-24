# The reference game's numbers (read from the purchased package, kept out of the repo) run through the same player and rules.
# Reference only: nothing here is shipped.
import math, sys, json
sys.argv=[sys.argv[0]]
import model
from model import Sim, ND, play, fmt
rows=[l for l in open('/tmp/orig/tables.txt').read().split('\n')]
def table(name):
    i=rows.index('##### '+name); out=[]
    for l in rows[i+3:]:
        if l.startswith('#####') or not l.strip(): break
        out.append(l.split(','))
    return out
B=table('building'); U=table('storeUpgrade'); M=table('supermarket')
class O: pass
o=O(); o.Session=90; o.Offline=360; o.TruckEvery=50/60
o.buildPrice=[float(r[2]) for r in B]; o.basePrice=[float(r[4]) for r in B]; o.upBase=[float(r[5]) for r in B]; o.upStep=[float(r[6]) for r in B]; o.upRate=[float(r[7]) for r in B]
o.emp=[[float(x) for x in r[10].split(':')] for r in B]; o.prodMax=[int(r[12]) for r in B]; o.prodBase=[float(r[13]) for r in B]; o.prodRate=[float(r[14]) for r in B]
o.speed=[float(r[15]) for r in B]; o.speedStep=[float(r[16]) for r in B]
o.tiers=[[] for _ in range(ND)]
for r in U: o.tiers[int(r[1])-1].append((int(r[3]),float(r[4])))
o.maxLv=[t[-1][0]-1 for t in o.tiers]
o.starCost=[float(r[3]) for r in M]; o.starProfit=[float(r[4]) for r in M]
o.visit=[90,90,90,70,60,50,40,30,20,10,5]; o.Visit=o.visit
o.park=[50,1e3,1e4,15e4,1e6,1e7,25e7,1e11,1e13,1e14,1e15,25e15,5e17,975e15,145e16,1925e15,24e17,2875e15,335e20,3825e24,43e28,4775e32]
o.cashOpen=[0,100,1e3,25e4,1e11,1e13,1e15,1e17]; o.cashUpBase=[5,5,15,250,1200,2500,1e4,1e4]; o.cashUpRate=[1.6,1.6,1.9,2,2.1,2.15,2.2,2.2]
o.cashStep=[.1,.1,.1,.1,.2,.2,.24,.28]; o.cashBase=[5,5,7,8,10,12,14,14]   # checkout base speed not found in the package; ours used
o.Stay=1.3; o.ParkPer=6; o.CarsBase=8; o.CarsStep=0.8
o.Base=o.basePrice
class OSim(Sim):
    def __init__(s,t): super().__init__(t); s.coin=1000.0
    def mult(s): return s.t.starProfit[s.star]
    def tierMul(s,d):
        m=1; start=0
        for lr,rate in s.t.tiers[d]:
            if s.lv[d]>=start: m*=rate
            start=lr
        return m
    def price(s,d): return (s.t.basePrice[d]+(s.lv[d]-1)*s.t.upStep[d])*s.tierMul(d)*s.mult()
    def staffSpeed(s,d): return s.t.speed[d]+s.sp[d]*s.t.speedStep[d]
    def arrivals(s): return min(s.t.CarsBase+s.t.CarsStep*(s.ad-1), s.t.ParkPer*s.park/s.t.Stay)
    def cash(s): return sum(s.t.cashBase[c]+(s.cl[c]-1)*s.t.cashStep[c] for c in range(8) if s.cl[c]>0)
    def levelCost(s,d): return math.inf if s.lv[d]>=s.t.maxLv[d] else round(s.t.upRate[d]**(s.lv[d]-1)*s.t.upBase[d],2)
    def hireCost(s,d): return math.inf if s.st[d]>=5 else s.t.emp[d][s.st[d]-1]
    def speedCost(s,d): return math.inf if s.sp[d]>=s.t.prodMax[d] else s.t.prodBase[d]*s.t.prodRate[d]**s.sp[d]
    def adCost(s): return math.inf if s.ad>=100 else 2**(s.ad+1)
    def parkCost(s): return math.inf if s.park>len(s.t.park) else s.t.park[s.park-1]
    def cashOpenCost(s):
        n=sum(1 for c in s.cl if c>0); return math.inf if n>=8 else s.t.cashOpen[n]
    def cashUpCost(s,c): return math.inf if s.cl[c]<=0 or s.cl[c]>=50 else s.t.cashUpBase[c]*s.t.cashUpRate[c]**(s.cl[c]-1)
    def options(s):
        o=[]
        nx=next((d for d in range(ND) if not s.op[d]),-1)
        if nx>=0: o.append(('build',nx,s.t.buildPrice[nx]))
        if s.star+1<len(s.t.starCost): o.append(('star',0,s.t.starCost[s.star+1]))
        for d in range(ND):
            if s.op[d]: o+=[('lv',d,s.levelCost(d)),('hire',d,s.hireCost(d)),('speed',d,s.speedCost(d))]
        o+=[('ad',0,s.adCost()),('park',0,s.parkCost()),('copen',0,s.cashOpenCost())]
        for c in range(8): o.append(('cup',c,s.cashUpCost(c)))
        return [x for x in o if x[2]<math.inf]
model.Sim=OSim
o.ParkCost=o.park; o.MaxLevel=None
model.report(o)
