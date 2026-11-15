--!nonstrict
-- Cooperative time-slicing: a match step on the client (shared/LocalMatch)
-- runs as a job — a coroutine resumed once per frame with a time budget. The simulation's long loops call
-- `Coop.check()`: inside a job whose budget is spent it yields, and the step goes on in the next frame,
-- so a heavy step (a big battle, a route search) never stalls a frame. Outside a job (the server, tests)
-- it is a cheap no-op and every step runs whole.
--
-- Route searches run in their own threads (task.spawn); they call `Coop.pace(p)` instead, which gives the
-- frame back (task.wait) after SLICE seconds of work.
local RunService=game:GetService("RunService")
local Coop={}
local current=nil
local deadline=0
-- Work between two yields of a route search: a frame's share on a client, more on a server.
-- (2.5 ms since 2026-11-15: these threads run beside the match step's own budget, several at once in
-- a late solo match, and 4 ms each was more than an old phone's frame could spare)
Coop.SLICE=RunService:IsClient()and .0025 or .015
-- Loading (the grid, a new match): bigger slices — each yield waits a whole frame, and hundreds of small
-- ones made the start several times slower than the work itself.
Coop.LOAD_SLICE=RunService:IsClient()and .012 or .05

function Coop.check()
 if current and os.clock()>=deadline and coroutine.running()==current then coroutine.yield()end
end
function Coop.active()return current~=nil and coroutine.running()==current end
-- For loops in threads of their own: `local p={t=os.clock()}` before the loop, `Coop.pace(p)` inside.
function Coop.pace(p)
 if os.clock()-p.t<Coop.SLICE then return end
 if Coop.active()then coroutine.yield()else task.wait()end
 p.t=os.clock()
end
-- Loading loops: `local p={t=os.clock()}` before, `Coop.loadPace(p)` every few thousand items.
function Coop.loadPace(p)
 if os.clock()-p.t<Coop.LOAD_SLICE then return end
 if Coop.active()then coroutine.yield()else task.wait()end
 p.t=os.clock()
end
-- A plain yield that is safe inside a job too (task.wait there would let the scheduler resume the job
-- behind our back).
function Coop.wait()if Coop.active()then coroutine.yield()else task.wait()end end
-- job = Coop.job(fn, ...); job:step(budget) -> true once finished (job.ok, job.err).
function Coop.job(fn,...)
 local args=table.pack(...)
 local job={done=false,ok=nil,err=nil}
 job.co=coroutine.create(function()return fn(table.unpack(args,1,args.n))end)
 function job:step(budget)
  if self.done then return true end
  local prev,prevDeadline=current,deadline
  current=self.co;deadline=os.clock()+budget
  local ok,err=coroutine.resume(self.co)
  current,deadline=prev,prevDeadline
  if coroutine.status(self.co)=='dead'or not ok then self.done=true;self.ok=ok;self.err=not ok and err or nil end
  return self.done
 end
 return job
end
return Coop
