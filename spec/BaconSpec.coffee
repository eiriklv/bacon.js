expect = require("chai").expect
Bacon = (require "../src/Bacon").Bacon
Mocks = (require "./Mock")
TickScheduler = (require "./TickScheduler").TickScheduler
mock = Mocks.mock
mockFunction = Mocks.mockFunction
EventEmitter = require("events").EventEmitter
th = require("./SpecHelper")
t = th.t
expectStreamEvents = th.expectStreamEvents
expectPropertyEvents = th.expectPropertyEvents
verifyCleanup = th.verifyCleanup
error = th.error
soon = th.soon
series = th.series
repeat = th.repeat
toValues = th.toValues
sc = TickScheduler()
Bacon.scheduler = sc

describe "Bacon.later", ->
  describe "should send single event and end", ->
    expectStreamEvents( 
      -> Bacon.later(t(1), "lol")
      ["lol"])
  describe "supports sending an Error event as well", ->
    expectStreamEvents(
      -> Bacon.later(t(1), new Bacon.Error("oops"))
      [error()])

describe "Bacon.sequentially", ->
  describe "should send given events and end", ->
    expectStreamEvents(
      -> Bacon.sequentially(t(1), ["lol", "wut"])
      ["lol", "wut"])
  describe "include error events", ->
    expectStreamEvents(
      -> Bacon.sequentially(t(1), [error(), "lol"])
      [error(), "lol"])
  describe "will stop properly even when exception thrown by subscriber", ->
    expectStreamEvents(
      ->
        s = Bacon.sequentially(t(1), ["lol", "wut"])
        s.onValue (value) ->
          throw "testing"
        s
      [])

describe "Bacon.interval", ->
  describe "repeats single element indefinitely", ->
    expectStreamEvents(
      -> Bacon.interval(t(1), "x").take(3)
      ["x", "x", "x"])

testLiftedCallback = (src, liftedCallback) ->
  input = [
    Bacon.constant('a')
    'x'
    Bacon.constant('b').toProperty()
    'y'
  ]
  output = ['a', 'x', 'b', 'y']
  expectStreamEvents(
    -> liftedCallback(src, input...)
    [output]
  )


describe "Bacon.fromCallback", ->
  describe "makes an EventStream from function that takes a callback", ->
    expectStreamEvents(
      ->
        src = (callback) -> callback("lol")
        stream = Bacon.fromCallback(src)
      ["lol"])
  describe "supports partial application", ->
    expectStreamEvents(
      ->
        src = (param, callback) -> callback(param)
        stream = Bacon.fromCallback(src, "lol")
      ["lol"])
  describe "supports partial application with Observable arguments", ->
    testLiftedCallback(
      (values..., callback) -> callback(values)
      Bacon.fromCallback
    )

describe "Bacon.fromNodeCallback", ->
  describe "makes an EventStream from function that takes a node-style callback", ->
    expectStreamEvents(
      ->
        src = (callback) -> callback(null, "lol")
        stream = Bacon.fromNodeCallback(src)
      ["lol"])
  describe "handles error parameter correctly", ->
    expectStreamEvents(
      ->
        src = (callback) -> callback('errortxt', null)
        stream = Bacon.fromNodeCallback(src)
      [error()])
  describe "supports partial application", ->
    expectStreamEvents(
      ->
        src = (param, callback) -> callback(null, param)
        stream = Bacon.fromNodeCallback(src, "lol")
      ["lol"])
  describe "supports partial application with Observable arguments", ->
    testLiftedCallback(
      (values..., callback) -> callback(null, values)
      Bacon.fromNodeCallback
    )

# Wrap EventEmitter as EventTarget
toEventTarget = (emitter) ->
  addEventListener: (event, handler) -> 
    emitter.addListener(event, handler)
  removeEventListener: (event, handler) -> emitter.removeListener(event, handler)

describe "Bacon.fromEventTarget", ->
  soon = (f) -> setTimeout f, 0
  describe "should create EventStream from DOM object", ->
    expectStreamEvents(
      -> 
        emitter = new EventEmitter()
        emitter.on "newListener", ->
          soon -> emitter.emit "click", "x"
        element = toEventTarget emitter
        Bacon.fromEventTarget(element, "click").take(1)
      ["x"]
    )

  describe "should create EventStream from EventEmitter", ->
    expectStreamEvents(
      -> 
        emitter = new EventEmitter()
        emitter.on "newListener", ->
          soon -> emitter.emit "data", "x"
        Bacon.fromEventTarget(emitter, "data").take(1)
      ["x"]
    )

  describe "should allow a custom map function for EventStream from EventEmitter", ->
    expectStreamEvents(
      -> 
        emitter = new EventEmitter()
        emitter.on "newListener", ->
          soon -> emitter.emit "data", "x", "y"
        Bacon.fromEventTarget(emitter, "data", (x, y) => [x, y]).take(1)
      [["x", "y"]]
    )


  it "should clean up event listeners from EventEmitter", ->
    emitter = new EventEmitter()
    Bacon.fromEventTarget(emitter, "data").take(1).subscribe ->
    emitter.emit "data", "x"
    expect(emitter.listeners("data").length).to.deep.equal(0)

  it "should clean up event listeners from DOM object", ->
    emitter = new EventEmitter()
    element = toEventTarget emitter
    dispose = Bacon.fromEventTarget(element, "click").subscribe ->
    dispose()
    expect(emitter.listeners("click").length).to.deep.equal(0)

describe "Observable.log", ->
  preservingLog = (f) ->
    originalConsole = console
    originalLog = console.log
    try
      f()
    finally
      global.console = originalConsole
      console.log = originalLog

  it "does not crash", ->
    preservingLog ->
      console.log = ->
      Bacon.constant(1).log()
  it "does not crash in case console.log is not defined", ->
    preservingLog ->
      console.log = undefined
      Bacon.constant(1).log()

describe "Observable.slidingWindow", ->
  describe "slides the window for EventStreams", ->
    expectPropertyEvents(
      -> series(1, [1,2,3]).slidingWindow(2)
      [[], [1], [1,2], [2,3]])
  describe "slides the window for Properties", ->
    expectPropertyEvents(
      -> series(1, [1,2,3]).toProperty().slidingWindow(2)
      [[], [1], [1,2], [2,3]])
  describe "accepts second parameter for minimum amount of values", ->
    expectPropertyEvents(
      -> series(1, [1,2,3,4]).slidingWindow(3, 2)
      [[1,2], [1,2,3], [2,3,4]])
    expectPropertyEvents(
      -> series(1, [1,2,3,4]).toProperty(0).slidingWindow(3, 2)
      [[0,1], [0, 1, 2], [1,2,3], [2,3,4]])

describe "EventStream.filter", ->
  describe "should filter values", ->
    expectStreamEvents(
      -> series(1, [1, 2, error(), 3]).filter(lessThan(3))
      [1, 2, error()])
  describe "extracts field values", ->
    expectStreamEvents(
      -> series(1, [{good:true, value:"yes"}, {good:false, value:"no"}]).filter(".good").map(".value")
      ["yes"])
  describe "can filter by Property value", ->
    expectStreamEvents(
      ->
        src = series(1, [1,1,2,3,4,4,8,7])
        odd = src.map((x) -> x % 2).toProperty()
        src.filter(odd)
      [1,1,3,7])

describe "EventStream.map", ->
  describe "should map with given function", ->
    expectStreamEvents(
      -> series(1, [1, 2, 3]).map(times, 2)
      [2, 4, 6])
  describe "also accepts a constant value", ->
    expectStreamEvents(
      -> series(1, [1, 2, 3,]).map("lol")
      ["lol", "lol", "lol"])
  describe "extracts property from value object", ->
    o = { lol : "wut" }
    expectStreamEvents(
      -> repeat(1, [o]).take(3).map(".lol")
      ["wut", "wut", "wut"])
  describe "extracts a nested property too", ->
    o = { lol : { wut : "wat" } }
    expectStreamEvents(
      -> Bacon.once(o).map(".lol.wut")
      ["wat"])
  describe "in case of a function property, calls the function with no args", ->
    expectStreamEvents(
      -> Bacon.once([1,2,3]).map(".length")
      [3])
  describe "allows arguments for methods", ->
    thing = { square: (x) -> x * x }
    expectStreamEvents(
      -> Bacon.once(thing).map(".square", 2)
      [4])
  describe "works with method call on given object, with partial application", ->
    multiplier = { multiply: (x, y) -> x * y }
    expectStreamEvents(
      -> series(1, [1,2,3]).map(multiplier, "multiply", 2)
      [2,4,6])
  describe "can map to a Property value", ->
    expectStreamEvents(
      -> series(1, [1,2,3]).map(Bacon.constant(2))
      [2,2,2])
  it "preserves laziness", ->
    calls = 0
    id = (x) -> 
      calls++
      x
    Bacon.fromArray([1,2,3,4,5]).map(id).skip(4).onValue()
    expect(calls).to.equal(1)

describe "EventStream.mapError", ->
  describe "should map error events with given function", ->
    expectStreamEvents(
        -> repeat(1, [1, error("OOPS")]).mapError(id).take(2)
        [1, "OOPS"])
  describe "also accepts a constant value", ->
    expectStreamEvents(
        -> repeat(1, [1, error()]).mapError("ERR").take(2)
        [1, "ERR"])

describe "EventStream.doAction", ->
  it "calls function before sending value to listeners", ->
    called = []
    bus = new Bacon.Bus()
    s = bus.doAction((x) -> called.push(x))
    s.onValue(->)
    s.onValue(->)
    bus.push(1)
    expect(called).to.deep.equal([1])
  describe "does not alter the stream", ->
    expectStreamEvents(
      -> series(1, [1, 2]).doAction(->)
      [1, 2])

describe "EventStream.mapEnd", ->
  describe "produces an extra element on stream end", ->
    expectStreamEvents(
      -> series(1, ["1", error()]).mapEnd("the end")
      ["1", error(), "the end"])
  describe "accepts either a function or a constant value", ->
    expectStreamEvents(
      -> series(1, ["1", error()]).mapEnd(-> "the end")
      ["1", error(), "the end"])
  describe "works with undefined value as well", ->
    expectStreamEvents(
      -> series(1, ["1", error()]).mapEnd()
      ["1", error(), undefined])

describe "EventStream.take", ->
  describe "takes N first elements", ->
    expectStreamEvents(
      -> series(1, [1,2,3,4]).take(2)
      [1,2])
  describe "works with N=0", ->
    expectStreamEvents(
      -> series(1, [1,2,3,4]).take(0)
      [])
  describe "will stop properly even when exception thrown by subscriber", ->
    expectStreamEvents(
      ->
        s = Bacon.repeatedly(t(1), ["lol", "wut"]).take(2)
        s.onValue (value) ->
          throw "testing"
        s
      [])
  describe "works with synchronous source", ->
    expectStreamEvents(
      -> Bacon.fromArray([1,2,3,4]).take(2)
      [1,2])

describe "EventStream.takeWhile", ->
  describe "takes while predicate is true", ->
    expectStreamEvents(
      -> repeat(1, [1, error("wat"), 2, 3]).takeWhile(lessThan(3))
      [1, error("wat"), 2])
  describe "extracts field values", ->
    expectStreamEvents(
      -> series(1, [{good:true, value:"yes"}, {good:false, value:"no"}])
           .takeWhile(".good").map(".value")
      ["yes"])
  describe "can filter by Property value", ->
    expectStreamEvents(
      ->
        src = series(1, [1,1,2,3,4,4,8,7])
        odd = src.map((x) -> x % 2).toProperty()
        src.takeWhile(odd)
      [1,1])
  describe "works with synchronous source", ->
    expectStreamEvents(
      -> Bacon.fromArray([1, 2, 3]).takeWhile(lessThan(3))
      [1, 2])

describe "EventStream.skip", ->
  describe "should skip first N items", ->
    expectStreamEvents(
      -> series(1, [1, error(), 2, error(), 3]).skip(1)
    [error(), 2, error(), 3])
  describe "accepts N <= 0", ->
    expectStreamEvents(
      -> series(1, [1, 2]).skip(-1)
    [1, 2])
  describe "works with synchronous source", ->
    expectStreamEvents(
      -> Bacon.fromArray([1, 2, 3]).skip(1)
    [2, 3])

describe "EventStream.skipWhile", ->
  describe "skips filter predicate holds true", ->
    expectStreamEvents(
      -> series(1, [1, error(), 2, error(), 3, 2]).skipWhile(lessThan(3))
      [error(), error(), 3, 2])
  describe "extracts field values", ->
    expectStreamEvents(
      -> series(1, [{good:true, value:"yes"}, {good:false, value:"no"}])
           .skipWhile(".good").map(".value")
      ["no"])
  describe "can filter by Property value", ->
    expectStreamEvents(
      ->
        src = series(1, [1,1,2,3,4,4,8,7])
        odd = src.map((x) -> x % 2).toProperty()
        src.skipWhile(odd)
      [2,3,4,4,8,7])
  describe "for synchronous sources", ->
    describe "skips filter predicate holds true", ->
      expectStreamEvents(
        -> Bacon.fromArray([1, 2, 3, 2]).skipWhile(lessThan(3))
        [3, 2])

describe "EventStream.skipUntil", ->
  describe "skips events until one appears in given starter stream", ->
    expectStreamEvents(
      ->
        src = series(3, [1,2,3])
        src.onValue(->) # to start "time" immediately instead of on subscribe
        starter = series(4, ["start"])
        src.skipUntil(starter)
      [2,3])
  describe "works with self-derived starter", ->
    expectStreamEvents(
      ->
        src = series(3, [1,2,3])
        starter = src.filter((x) -> x == 3)
        src.skipUntil(starter)
      [3])

describe "EventStream.skipDuplicates", ->
  it "Drops duplicates with subscribers with non-overlapping subscription time (#211)", ->
    b = new Bacon.Bus()
    noDups = b.skipDuplicates()
    round = (expected) ->
      values = []
      noDups.take(1).onValue (x) -> values.push(x)
      b.push 1
      expect(values).to.deep.equal(expected)
    round([1])
    round([])
    round([])

  describe "drops duplicates", ->
    expectStreamEvents(
      -> series(1, [1, 2, error(), 2, 3, 1]).skipDuplicates()
    [1, 2, error(), 3, 1])

  describe "allows undefined as initial value", ->
    expectStreamEvents(
      -> series(1, [undefined, undefined, 1, 2]).skipDuplicates()
    [undefined, 1, 2])

  describe "works with custom isEqual function", ->
    a = {x: 1}; b = {x: 2}; c = {x: 2}; d = {x: 3}; e = {x: 1}
    isEqual = (a, b) -> a?.x == b?.x
    expectStreamEvents(
      -> series(1, [a, b, error(), c, d, e]).skipDuplicates(isEqual)
      [a, b, error(), d, e])
  
  describe "works with synchrounous sources", ->
    expectStreamEvents(
      -> Bacon.fromArray([1, 2, 2, 3, 1]).skipDuplicates()
    [1, 2, 3, 1])

describe "EventStream.flatMap", ->
  describe "should spawn new stream for each value and collect results into a single stream", ->
    expectStreamEvents(
      -> series(1, [1, 2]).flatMap (value) ->
        Bacon.sequentially(t(2), [value, error(), value])
      [1, 2, error(), error(), 1, 2])
  describe "should pass source errors through to the result", ->
    expectStreamEvents(
      -> series(1, [error(), 1]).flatMap (value) ->
        Bacon.later(t(1), value)
      [error(), 1])
  describe "should work with a spawned stream responding synchronously", ->
    expectStreamEvents(
      -> series(1, [1, 2]).flatMap (value) ->
         Bacon.never().concat(Bacon.once(value))
      [1, 2])
  describe "should work with a source stream responding synchronously", ->
    expectStreamEvents(
      -> Bacon.fromArray([1, 2]).flatMap (value) ->
         Bacon.once(value)
      [1, 2])
    expectStreamEvents(
      -> Bacon.fromArray([1, 2]).flatMap (value) ->
         Bacon.fromArray([value, value*10])
      [1, 10, 2, 20])
    expectStreamEvents(
      -> Bacon.once(1).flatMap (value) ->
         Bacon.later(0, value)
      [1])
  describe "Works also when f returns a Property instead of an EventStream", ->
    expectStreamEvents(
      -> series(1, [1,2]).flatMap(Bacon.constant)
      [1,2])
  describe "Works also when f returns a constant value instead of an EventStream", ->
    expectStreamEvents(
      -> series(1, [1,2]).flatMap((x) -> x)
      [1,2])
  describe "Accepts a constant EventStream/Property as an alternative to a function", ->
    expectStreamEvents(
      -> Bacon.once("asdf").flatMap(Bacon.constant("bacon"))
      ["bacon"])
    expectStreamEvents(
      -> Bacon.once("asdf").flatMap(Bacon.once("bacon"))
      ["bacon"])

describe "Property.flatMap", ->
  describe "should spawn new stream for all events including Init", ->
    expectStreamEvents(
      ->
        once = (x) -> Bacon.once(x)
        series(1, [1, 2]).toProperty(0).flatMap(once)
      [0, 1, 2])
  describe "Works also when f returns a Property instead of an EventStream", ->
    expectStreamEvents(
      -> series(1, [1,2]).toProperty().flatMap(Bacon.constant)
      [1,2])
    expectPropertyEvents(
      -> series(1, [1,2]).toProperty().flatMap(Bacon.constant).toProperty()
      [1,2])
  describe "works for synchronous source", ->
    expectStreamEvents(
      ->
        once = (x) -> Bacon.once(x)
        Bacon.fromArray([1, 2]).toProperty(0).flatMap(once)
      [0, 1, 2])

describe "EventStream.flatMapLatest", ->
  describe "spawns new streams but collects values from the latest spawned stream only", ->
    expectStreamEvents(
      -> series(3, [1, 2]).flatMapLatest (value) ->
        Bacon.sequentially(t(2), [value, error(), value])
      [1, 2, error(), 2])
  describe "Accepts a constant EventStream/Property as an alternative to a function", ->
    expectStreamEvents(
      -> Bacon.once("asdf").flatMapLatest(Bacon.constant("bacon"))
      ["bacon"])

describe "Property.flatMapLatest", ->
  describe "spawns new streams but collects values from the latest spawned stream only", ->
    expectStreamEvents(
      -> series(3, [1, 2]).toProperty(0).flatMapLatest (value) ->
        Bacon.sequentially(t(2), [value, value])
      [0, 1, 2, 2])
  describe "Accepts a constant EventStream/Property as an alternative to a function", ->
    expectStreamEvents(
      -> Bacon.constant("asdf").flatMapLatest(Bacon.constant("bacon"))
      ["bacon"])

describe "EventStream.flatMapFirst", ->
  describe "spawns new streams and ignores source events until current spawned stream has ended", ->
    expectStreamEvents(
      -> series(2, [2, 4, 6, 8]).flatMapFirst (value) ->
        series(1, ["a" + value, "b" + value, "c" + value])
      ["a2", "b2", "c2", "a6", "b6", "c6"])

describe "EventStream.merge", ->
  describe "merges two streams and ends when both are exhausted", ->
    expectStreamEvents(
      ->
        left = series(1, [1, error(), 2, 3])
        right = series(1, [4, 5, 6]).delay(t(4))
        left.merge(right)
      [1, error(), 2, 3, 4, 5, 6])
  describe "respects subscriber return value", ->
    expectStreamEvents(
      ->
        left = repeat(2, [1, 3]).take(3)
        right = repeat(3, [2]).take(3)
        left.merge(right).takeWhile(lessThan(2))
      [1])
  describe "does not duplicate same error from two streams", ->
    expectStreamEvents(
      ->
        src = series(1, [1, error(), 2, error(), 3])
        left = src.map((x) -> x)
        right = src.map((x) -> x * 2)
        left.merge(right)
      [1, 2, error(), 2, 4, error(), 3, 6])
  describe "works with synchronous sources", ->
    expectStreamEvents(
      -> Bacon.fromArray([1,2]).merge(Bacon.fromArray([3,4]))
      [1,2,3,4])

describe "EventStream.delay", ->
  describe "delays all events (except errors) by given delay in milliseconds", ->
    expectStreamEvents(
      ->
        left = series(2, [1, 2, 3])
        right = series(1, [error(), 4, 5, 6]).delay(t(6))
        left.merge(right)
      [error(), 1, 2, 3, 4, 5, 6])
  describe "works with synchronous streams", ->
    expectStreamEvents(
      ->
        left = Bacon.fromArray([1, 2, 3])
        right = Bacon.fromArray([4, 5, 6]).delay(t(6))
        left.merge(right)
      [1, 2, 3, 4, 5, 6])

describe "EventStream.debounce", ->
  describe "throttles input by given delay, passing-through errors", ->
    expectStreamEvents(
      -> series(2, [1, error(), 2]).debounce(t(7))
      [error(), 2])
  describe "waits for a quiet period before outputing anything", ->
    th.expectStreamTimings(
      -> series(2, [1, 2, 3, 4]).debounce(t(3))
      [[11, 4]])
  describe "works with synchronous source", ->
    expectStreamEvents(
      -> Bacon.fromArray([1, 2, 3, 4]).debounce(t(3))
      [4])


describe "EventStream.debounceImmediate(delay)", ->
  describe "outputs first event immediately, then ignores events for given amount of milliseconds", ->
    th.expectStreamTimings(
      -> series(2, [1, 2, 3, 4]).debounceImmediate(t(3))
      [[2, 1], [6, 3]])
  describe "works with synchronous source", ->
    expectStreamEvents(
      -> Bacon.fromArray([1, 2, 3, 4]).debounceImmediate(t(3))
      [1])

describe "EventStream.throttle(delay)", ->
  describe "outputs at steady intervals, without waiting for quiet period", ->
    th.expectStreamTimings(
      -> series(2, [1, 2, 3]).throttle(t(3))
      [[5, 2], [8, 3]])
  describe "works with synchronous source", ->
    expectStreamEvents(
      -> Bacon.fromArray([1, 2, 3]).throttle(t(3))
      [3])

describe "EventStream.bufferWithTime", ->
  describe "returns events in bursts, passing through errors", ->
    expectStreamEvents(
      -> series(2, [error(), 1, 2, 3, 4, 5, 6, 7]).bufferWithTime(t(7))
      [error(), [1, 2, 3, 4], [5, 6, 7]])
  describe "keeps constant output rate even when input is sporadical", ->
    th.expectStreamTimings(
      -> th.atGivenTimes([[0, "a"], [3, "b"], [5, "c"]]).bufferWithTime(t(2))
      [[2, ["a"]], [4, ["b"]], [6, ["c"]]]
    )
  describe "works with empty stream", ->
    expectStreamEvents(
      -> Bacon.never().bufferWithTime(t(1))
      [])
  describe "allows custom defer-function", ->
    fast = (f) -> sc.setTimeout(f, 0)
    th.expectStreamTimings(
      -> th.atGivenTimes([[0, "a"], [2, "b"]]).bufferWithTime(fast)
      [[0, ["a"]], [2, ["b"]]])
  describe "works with synchronous defer-function", ->
    sync = (f) -> f()
    th.expectStreamTimings(
      -> th.atGivenTimes([[0, "a"], [2, "b"]]).bufferWithTime(sync)
      [[0, ["a"]], [2, ["b"]]])
  describe "works with synchronous source", ->
    expectStreamEvents(
      -> series(2, [1,2,3]).bufferWithTime(t(7))
      [[1,2,3]])

describe "EventStream.bufferWithCount", ->
  describe "returns events in chunks of fixed size, passing through errors", ->
    expectStreamEvents(
      -> series(1, [1, 2, 3, error(), 4, 5]).bufferWithCount(2)
      [[1, 2], error(), [3, 4], [5]])
  describe "works with synchronous source", ->
    expectStreamEvents(
      -> Bacon.fromArray([1,2,3,4,5]).bufferWithCount(2)
      [[1, 2], [3, 4], [5]])

describe "EventStream.bufferWithTimeOrCount", ->
  describe "flushes on count", ->
    expectStreamEvents(
      -> series(1, [1, 2, 3, error(), 4, 5]).bufferWithTimeOrCount(t(10), 2)
      [[1, 2], error(), [3, 4], [5]])
  describe "flushes on timeout", ->
    expectStreamEvents(
      -> series(2, [error(), 1, 2, 3, 4, 5, 6, 7]).bufferWithTimeOrCount(t(7), 10)
      [error(), [1, 2, 3, 4], [5, 6, 7]])

describe "EventStream.takeUntil", ->
  describe "takes elements from source until an event appears in the other stream", ->
    expectStreamEvents(
      ->
        src = repeat(3, [1, 2, 3])
        stopper = repeat(7, ["stop!"])
        src.takeUntil(stopper)
      [1, 2])
  describe "works on self-derived stopper", ->
    expectStreamEvents(
      ->
        src = repeat(3, [3, 2, 1])
        stopper = src.filter(lessThan(3))
        src.takeUntil(stopper)
      [3])
  describe "includes source errors, ignores stopper errors", ->
    expectStreamEvents(
      ->
        src = repeat(2, [1, error(), 2, 3])
        stopper = repeat(7, ["stop!"]).merge(repeat(1, [error()]))
        src.takeUntil(stopper)
      [1, error(), 2])
  describe "works with Property as stopper", ->
    expectStreamEvents(
      ->
        src = repeat(3, [1, 2, 3])
        stopper = repeat(7, ["stop!"]).toProperty()
        src.takeUntil(stopper)
      [1, 2])
  describe "considers Property init value as stopper", ->
    expectStreamEvents(
      ->
        src = repeat(3, [1, 2, 3])
        stopper = Bacon.constant("stop")
        src.takeUntil(stopper)
      [])
  describe "ends immediately with synchronous stopper", ->
    expectStreamEvents(
      ->
        src = repeat(3, [1, 2, 3])
        stopper = Bacon.once("stop")
        src.takeUntil(stopper)
      [])
  describe "ends properly with a never-ending stopper", ->
    expectStreamEvents(
      ->
        src = series(1, [1,2,3])
        stopper = new Bacon.Bus()
        src.takeUntil(stopper)
      [1,2,3])
  describe "unsubscribes its source as soon as possible", ->
     expectStreamEvents(
       ->
        startTick = sc.now()
        Bacon.later(20)
        .onUnsub(->
          expect(sc.now()).to.equal(startTick + 1))
        .takeUntil Bacon.later(1)
      [])
  describe "it should unsubscribe its stopper on end", ->
     expectStreamEvents(
       -> 
         startTick = sc.now()
         Bacon.later(1,'x').takeUntil(Bacon.later(20).onUnsub(->
           expect(sc.now()).to.equal(startTick + 1)))
       ['x'])
  describe "it should unsubscribe its stopper on no more", ->
     expectStreamEvents(
       -> 
         startTick = sc.now()
         Bacon.later(1,'x').takeUntil(Bacon.later(20).onUnsub(->
           expect(sc.now()).to.equal(startTick + 1)))
       ['x'])

describe "When an Event triggers another one in the same stream, while dispatching", ->
  it "Delivers triggered events correctly", ->
    bus = new Bacon.Bus
    values = []
    bus.take(2).onValue (v) ->
      bus.push "A"
      bus.push "B"
    bus.onValue (v) ->
      values.push(v)
    bus.push "a"
    bus.push "b"
    expect(values).to.deep.equal(["a", "A", "B", "A", "B", "b"])
  it "EventStream.take(1) works correctly (bug fix)", ->
    bus = new Bacon.Bus
    values = []
    bus.take(1).onValue (v) ->
      bus.push("onValue triggers a side-effect here")
      values.push(v)
    bus.push("foo")
    expect(values).to.deep.equal(["foo"])

describe "EventStream.awaiting(other)", ->
  describe "indicates whether s1 has produced output after s2 (or only the former has output so far)", ->
    expectPropertyEvents(
      -> series(2, [1, 1]).awaiting(series(3, [2]))
      [false, true, false, true])
  describe "supports Properties", ->
    expectPropertyEvents(
      -> series(2, [1, 1]).awaiting(series(3, [2]).toProperty())
      [false, true, false, true])

describe "EventStream.endOnError", ->
  describe "terminates on error", ->
    expectStreamEvents(
      -> repeat(1, [1, 2, error(), 3]).endOnError()
      [1, 2, error()])
  describe "works with synchronous source", ->
    expectStreamEvents(
      -> Bacon.fromArray([1, 2, error(), 3]).endOnError()
      [1, 2, error()])

describe "Bacon.constant", ->
  describe "creates a constant property", ->
    expectPropertyEvents(
      -> Bacon.constant("lol")
    ["lol"])
  it "ignores unsubscribe", ->
    Bacon.constant("lol").onValue(=>)()
  describe "provides same value to all listeners", ->
    c = Bacon.constant("lol")
    expectPropertyEvents((-> c), ["lol"])
    it "check check", ->
      f = mockFunction()
      c.onValue(f)
      f.verify("lol")
  it "provides same value to all listeners, when mapped (bug fix)", ->
    c = Bacon.constant("lol").map(id)
    f = mockFunction()
    c.onValue(f)
    f.verify("lol")
    c.onValue(f)
    f.verify("lol")

describe "Bacon.never", ->
  describe "should send just end", ->
    expectStreamEvents(
      -> Bacon.never()
      [])

describe "Bacon.once", ->
  describe "should send single event and end", ->
    expectStreamEvents(
      -> Bacon.once("pow")
      ["pow"])
  describe "accepts an Error event as parameter", ->
    expectStreamEvents(
      -> Bacon.once(new Bacon.Error("oop"))
      [error()])

describe "EventStream.concat", ->
  describe "provides values from streams in given order and ends when both are exhausted", ->
    expectStreamEvents(
      ->
        left = series(2, [1, error(), 2, 3])
        right = series(1, [4, 5, 6])
        left.concat(right)
      [1, error(), 2, 3, 4, 5, 6])
  describe "respects subscriber return value when providing events from left stream", ->
    expectStreamEvents(
      ->
        left = repeat(3, [1, 3]).take(3)
        right = repeat(2, [1]).take(3)
        left.concat(right).takeWhile(lessThan(2))
      [1])
  describe "respects subscriber return value when providing events from right stream", ->
    expectStreamEvents(
      ->
        left = series(3, [1, 2])
        right = series(2, [2, 4, 6])
        left.concat(right).takeWhile(lessThan(4))
      [1, 2, 2])
  describe "works with Bacon.never()", ->
    expectStreamEvents(
      -> Bacon.never().concat(Bacon.never())
      [])
  describe "works with Bacon.once()", ->
    expectStreamEvents(
      -> Bacon.once(2).concat(Bacon.once(1))
      [2, 1])
  describe "works with Bacon.once() and Bacon.never()", ->
    expectStreamEvents(
      -> Bacon.once(1).concat(Bacon.never())
      [1])
  describe "works with Bacon.never() and Bacon.once()", ->
    expectStreamEvents(
      -> Bacon.never().concat(Bacon.once(1))
      [1])
  describe "works with Bacon.once() and async source", ->
    expectStreamEvents(
      -> Bacon.once(1).concat(series(1, [2, 3]))
      [1, 2, 3])
  describe "works with Bacon.once() and Bacon.fromArray()", ->
    expectStreamEvents(
      -> Bacon.once(1).concat(Bacon.fromArray([2, 3]))
      [1, 2, 3])

describe "EventStream.startWith", ->
  describe "provides seed value, then the rest", ->
    expectStreamEvents(
      ->
        left = series(1, [1, 2, 3])
        left.startWith('pow')
      ['pow', 1, 2, 3])
  describe "works with synchronous source", ->
    expectStreamEvents(
      ->
        left = Bacon.fromArray([1, 2, 3])
        left.startWith('pow')
      ['pow', 1, 2, 3])

describe "EventStream.toProperty", ->
  describe "delivers current value and changes to subscribers", ->
    expectPropertyEvents(
      ->
        s = new Bacon.Bus()
        p = s.toProperty("a")
        soon ->
          s.push "b"
          s.end()
        p
      ["a", "b"])
  describe "passes through also Errors", ->
    expectPropertyEvents(
      -> series(1, [1, error(), 2]).toProperty()
      [1, error(), 2])

  describe "supports null as value", ->
    expectPropertyEvents(
      -> series(1, [null, 1, null]).toProperty(null)
      [null, null, 1, null])

  describe "does not get messed-up by a transient subscriber (bug fix)", ->
    expectPropertyEvents(
      ->
        prop = series(1, [1,2,3]).toProperty(0)
        prop.subscribe (event) =>
          Bacon.noMore
        prop
      [0, 1, 2, 3])
  describe "works with synchronous source", ->
    expectPropertyEvents(
      -> Bacon.fromArray([1,2,3]).toProperty()
      [1,2,3])
    expectPropertyEvents(
      -> Bacon.fromArray([1,2,3]).toProperty(0)
      [0,1,2,3])
  it "preserves laziness", ->
    calls = 0
    id = (x) -> 
      calls++
      x
    Bacon.fromArray([1,2,3,4,5]).map(id).toProperty().skip(4).onValue()
    expect(calls).to.equal(1)

describe "Property.toEventStream", ->
  describe "creates a stream that starts with current property value", ->
    expectStreamEvents(
      -> series(1, [1, 2]).toProperty(0).toEventStream()
      [0, 1, 2])
  describe "works with synchronous source", ->
    expectStreamEvents(
      -> Bacon.fromArray([1, 2]).toProperty(0).toEventStream()
      [0, 1, 2])

describe "Property.toProperty", ->
  describe "returns the same Property", ->
    expectPropertyEvents(
      -> Bacon.constant(1).toProperty()
      [1])
  it "rejects arguments", ->
    try
      Bacon.constant(1).toProperty(0)
      fail()
    catch e

describe "Property.map", ->
  describe "maps property values", ->
    expectPropertyEvents(
      ->
        s = new Bacon.Bus()
        p = s.toProperty(1).map(times, 2)
        soon ->
          s.push 2
          s.error()
          s.end()
        p
      [2, 4, error()])

describe "Property.filter", ->
  describe "should filter values", ->
    expectPropertyEvents(
      -> series(1, [1, error(), 2, 3]).toProperty().filter(lessThan(3))
      [1, error(), 2])
  it "preserves old current value if the updated value is non-matching", ->
    s = new Bacon.Bus()
    p = s.toProperty().filter(lessThan(2))
    p.onValue(=>) # to ensure that property is actualy updated
    s.push(1)
    s.push(2)
    values = []
    p.onValue((v) => values.push(v))
    expect(values).to.deep.equal([1])
  describe "can filter by Property value", ->
    expectPropertyEvents(
      ->
        src = series(2, [1, 2, 3, 4]).delay(t(1)).toProperty()
        ok = series(2, [false, true, true, false]).toProperty()
        src.filter(ok)
      [2, 3])

describe "Property.take(1)", ->
  describe "takes the Initial event", ->
    expectPropertyEvents(
      -> series(1, [1,2,3]).toProperty(0).take(1)
      [0])
  describe "takes the first Next event, if no Initial value", ->
    expectPropertyEvents(
      -> series(1, [1,2,3]).toProperty().take(1)
      [1])
  describe "works for constants", ->
    expectPropertyEvents(
      -> Bacon.constant(1)
      [1])
  describe "works for never-ending Property", ->
    expectPropertyEvents(
      -> repeat(1, [1,2,3]).toProperty(0).take(1)
      [0])
    expectPropertyEvents(
      -> repeat(1, [1,2,3]).toProperty().take(1)
      [1])

describe "Bacon.once().take(1)", ->
  describe "works", ->
    expectStreamEvents(
      -> Bacon.once(1).take(1)
      [1])

describe "Property.takeWhile", ->
  describe "takes while predicate is true", ->
    expectPropertyEvents(
      -> series(1, [1, error("wat"), 2, 3])
        .toProperty()
        .takeWhile(lessThan(3))
      [1, error("wat"), 2])
  describe "extracts field values", ->
    expectPropertyEvents(
      -> series(1, [{good:true, value:"yes"}, {good:false, value:"no"}])
           .toProperty()
           .takeWhile(".good").map(".value")
      ["yes"])
  describe "can filter by Property value", ->
    expectPropertyEvents(
      ->
        src = series(1, [1,1,2,3,4,4,8,7]).toProperty()
        odd = src.map((x) -> x % 2)
        src.takeWhile(odd)
      [1,1])
  describe "works with never-ending Property", ->
    expectPropertyEvents(
      -> repeat(1, [1, error("wat"), 2, 3])
        .toProperty()
        .takeWhile(lessThan(3))
      [1, error("wat"), 2])

describe "Property.takeUntil", ->
  describe "takes elements from source until an event appears in the other stream", ->
    expectPropertyEvents(
      -> series(2, [1,2,3]).toProperty().takeUntil(Bacon.later(t(3)))
      [1])
  describe "works with errors", ->
    expectPropertyEvents(
      ->
        src = repeat(2, [1, error(), 3])
        stopper = repeat(5, ["stop!"])
        src.toProperty(0).takeUntil(stopper)
      [0, 1, error()])

describe "Property.delay", ->
  describe "delivers initial value and changes", ->
    expectPropertyEvents(
      -> series(1, [1,2,3]).toProperty(0).delay(t(1))
      [0,1,2,3])
  describe "delays changes", ->
    expectStreamEvents(
      -> series(2, [1,2,3]).toProperty()
        .delay(t(2)).changes().takeUntil(Bacon.later(t(5)))
      [1])
  describe "does not delay initial value", ->
    expectPropertyEvents(
      -> series(3, [1]).toProperty(0).delay(1).takeUntil(Bacon.later(t(2)))
      [0])

describe "Property.debounce", ->
  describe "delivers initial value and changes", ->
    expectPropertyEvents(
      -> series(2, [1,2,3]).toProperty(0).debounce(t(1))
      [0,1,2,3])
  describe "throttles changes, but not initial value", ->
    expectPropertyEvents(
      -> series(1, [1,2,3]).toProperty(0).debounce(t(4))
      [0,3])
  describe "works without initial value", ->
    expectPropertyEvents(
      -> series(2, [1,2,3]).toProperty().debounce(t(4))
      [3])
  describe "works with Bacon.constant (bug fix)", ->
    expectPropertyEvents(
      -> Bacon.constant(1).debounce(1)
      [1])
describe "Property.throttle", ->
  describe "throttles changes, but not initial value", ->
    expectPropertyEvents(
      -> series(1, [1,2,3]).toProperty(0).throttle(t(4))
      [0,3])
  describe "works with Bacon.once (bug fix)", ->
    expectPropertyEvents(
      -> Bacon.once(1).toProperty().throttle(1)
      [1])

describe "Property.endOnError", ->
  describe "terminates on Error", ->
    expectPropertyEvents(
      -> series(2, [1, error(), 2]).toProperty().endOnError()
      [1, error()])

describe "Property.awaiting(other)", ->
  describe "indicates whether p1 has produced output after p2 (or only the former has output so far)", ->
    expectPropertyEvents(
      -> series(2, [1, 1]).toProperty().awaiting(series(3, [2]))
      [false, true, false, true])

describe "Property.skipDuplicates", ->
  describe "drops duplicates", ->
    expectPropertyEvents(
      -> series(1, [1, 2, error(), 2, 3, 1]).toProperty(0).skipDuplicates()
    [0, 1, 2, error(), 3, 1])
  describe "Doesn't skip initial value (bug fix #211)", ->
    b = new Bacon.Bus()
    p = b.toProperty()
    p.onValue -> # force property update
    s = p.skipDuplicates()
    b.push 'foo'

    describe "series 1", ->
      expectPropertyEvents((-> s.take(1)), ["foo"])
    describe "series 2", ->
      expectPropertyEvents((-> s.take(1)), ["foo"])
    describe "series 3", ->
      expectPropertyEvents((-> s.take(1)), ["foo"])

describe "Property.changes", ->
  describe "sends property change events", ->
    expectStreamEvents(
      ->
        s = new Bacon.Bus()
        p = s.toProperty("a").changes()
        soon ->
          s.push "b"
          s.error()
          s.end()
        p
      ["b", error()])
 describe "works with synchronous source", ->
   expectStreamEvents(
     -> Bacon.fromArray([1,2,3]).toProperty(0).changes()
     [1,2,3])

describe "Property.combine", ->
  describe "combines latest values of two properties, with given combinator function, passing through errors", ->
    expectPropertyEvents(
      ->
        left = series(2, [1, error(), 2, 3]).toProperty()
        right = series(2, [4, error(), 5, 6]).delay(t(1)).toProperty()
        left.combine(right, add)
      [5, error(), error(), 6, 7, 8, 9])
  describe "also accepts a field name instead of combinator function", ->
    expectPropertyEvents(
      ->
        left = series(1, [[1]]).toProperty()
        right = series(2, [[2]]).toProperty()
        left.combine(right, ".concat")
      [[1, 2]])

  describe "combines with null values", ->
    expectPropertyEvents(
      ->
        left = series(1, [null]).toProperty()
        right = series(1, [null]).toProperty()
        left.combine(right, (l, r)-> [l, r])
      [[null, null]])

  it "unsubscribes when initial value callback returns Bacon.noMore", ->
    calls = 0
    bus = new Bacon.Bus()
    other = Bacon.constant(["rolfcopter"])
    bus.toProperty(["lollerskates"]).combine(other, ".concat").subscribe (e) ->
      if !e.isInitial()
        calls += 1
      Bacon.noMore

    bus.push(["fail whale"])
    expect(calls).to.equal 0
  describe "does not duplicate same error from two streams", ->
    expectPropertyEvents(
      ->
        src = series(1, ["same", error()])
        Bacon.combineAsArray(src, src)
      [["same", "same"], error()])

describe "EventStream.combine", ->
  describe "converts stream to Property, then combines", ->
    expectPropertyEvents(
      ->
        left = series(2, [1, error(), 2, 3])
        right = series(2, [4, error(), 5, 6]).delay(t(1)).toProperty()
        left.combine(right, add)
      [5, error(), error(), 6, 7, 8, 9])

describe "Property update is atomic", ->
  describe "in a diamond-shaped combine() network", ->
    expectPropertyEvents(
      ->
         a = series(1, [1, 2]).toProperty()
         b = a.map (x) -> x
         c = a.map (x) -> x
         b.combine(c, (x, y) -> x + y)
      [2, 4])
  describe "in a triangle-shaped combine() network", ->
    expectPropertyEvents(
      ->
         a = series(1, [1, 2]).toProperty()
         b = a.map (x) -> x
         a.combine(b, (x, y) -> x + y)
      [2, 4])
  describe "when filter is involved", ->
    expectPropertyEvents(
      ->
         a = series(1, [1, 2]).toProperty()
         b = a.map((x) -> x).filter(true)
         a.combine(b, (x, y) -> x + y)
      [2, 4])
  describe "when root property is based on combine*", ->
    expectPropertyEvents(
      ->
         a = series(1, [1, 2]).toProperty().combine(Bacon.constant(0), (x, y) -> x)
         b = a.map (x) -> x
         c = a.map (x) -> x
         b.combine(c, (x, y) -> x + y)
      [2, 4])
  describe "yet respects subscriber return values (bug fix)", ->
    expectStreamEvents(
      -> Bacon.repeatedly(t(1), [1, 2, 3]).toProperty().changes().take(1)
      [1])

describe "Bacon.combineAsArray", ->
  describe "initial value", ->
    event = null
    before ->
      prop = Bacon.constant(1)
      Bacon.combineAsArray(prop).subscribe (x) ->
        event = x if x.hasValue()
    it "is output as Initial event", ->
      expect(event.isInitial()).to.equal(true)
  describe "combines properties and latest values of streams, into a Property having arrays as values", ->
    expectPropertyEvents(
      ->
        stream = series(1, ["a", "b"])
        Bacon.combineAsArray([Bacon.constant(1), Bacon.constant(2), stream])
      [[1, 2, "a"], [1, 2, "b"]])
  describe "Works with streams provided as a list of arguments as well as with a single array arg", ->
    expectPropertyEvents(
      ->
        stream = series(1, ["a", "b"])
        Bacon.combineAsArray(Bacon.constant(1), Bacon.constant(2), stream)
      [[1, 2, "a"], [1, 2, "b"]])
  describe "works with single property", ->
    expectPropertyEvents(
      ->
        Bacon.combineAsArray([Bacon.constant(1)])
      [[1]])
  describe "works with single stream", ->
    expectPropertyEvents(
      ->
        Bacon.combineAsArray([Bacon.once(1)])
      [[1]])
  describe "works with arrays as values, with first array being empty (bug fix)", ->
    expectPropertyEvents(
      ->
        Bacon.combineAsArray([Bacon.constant([]), Bacon.constant([1])])
    ([[[], [1]]]))
  describe "works with arrays as values, with first array being non-empty (bug fix)", ->
    expectPropertyEvents(
      ->
        Bacon.combineAsArray([Bacon.constant([1]), Bacon.constant([2])])
    ([[[1], [2]]]))
  describe "works with empty array", ->
    expectPropertyEvents(
      -> Bacon.combineAsArray([])
      [[]])
  describe "accepts constant values instead of Observables", ->
    expectPropertyEvents(
      -> Bacon.combineAsArray(Bacon.constant(1), 2, 3)
    [[1,2,3]])
  it "preserves laziness", ->
    calls = 0
    id = (x) -> 
      calls++
      x
    Bacon.combineAsArray(Bacon.fromArray([1,2,3,4,5]).map(id)).skip(4).onValue()
    expect(calls).to.equal(1)

describe "Bacon.combineWith", ->
  describe "combines n properties, streams and constants using an n-ary function", ->
    expectPropertyEvents(
      ->
        stream = series(1, [1, 2])
        f = (x, y, z) -> x + y + z
        Bacon.combineWith(f, stream, Bacon.constant(10), 100)
      [111, 112])

describe "Boolean logic", ->
  describe "combines Properties with and()", ->
    expectPropertyEvents(
      -> Bacon.constant(true).and(Bacon.constant(false))
      [false])
  describe "combines Properties with or()", ->
    expectPropertyEvents(
      -> Bacon.constant(true).or(Bacon.constant(false))
      [true])
  describe "inverts property with not()", ->
    expectPropertyEvents(
      -> Bacon.constant(true).not()
      [false])
  describe "accepts constants instead of properties", ->
    expectPropertyEvents(
      -> Bacon.constant(true).and(false)
      [false])
    expectPropertyEvents(
      -> Bacon.constant(true).and(true)
      [true])
    expectPropertyEvents(
      -> Bacon.constant(true).or(false)
      [true])

describe "Bacon.mergeAll", ->
  describe ("merges all given streams"), ->
    expectStreamEvents(
      ->
        Bacon.mergeAll([
          series(3, [1, 2])
          series(3, [3, 4]).delay(t(1))
          series(3, [5, 6]).delay(t(2))])
      [1, 3, 5, 2, 4, 6])
  describe ("supports n-ary syntax"), ->
    expectStreamEvents(
      ->
        Bacon.mergeAll(
          series(3, [1, 2])
          series(3, [3, 4]).delay(t(1))
          series(3, [5, 6]).delay(t(2)))
      [1, 3, 5, 2, 4, 6])
  describe "returns empty stream for zero input", ->
    expectStreamEvents(
      -> Bacon.mergeAll([])
      [])

describe "Property.sampledBy(stream)", ->
  describe "samples property at events, resulting to EventStream", ->
    expectStreamEvents(
      ->
        prop = series(2, [1, 2]).toProperty()
        stream = repeat(3, ["troll"]).take(4)
        prop.sampledBy(stream)
      [1, 2, 2, 2])
  describe "includes errors from both Property and EventStream", ->
    expectStreamEvents(
      ->
        prop = series(2, [error(), 2]).toProperty()
        stream = series(3, [error(), "troll"])
        prop.sampledBy(stream)
      [error(), error(), 2])
  describe "ends when sampling stream ends", ->
    expectStreamEvents(
      ->
        prop = repeat(2, [1, 2]).toProperty()
        stream = repeat(2, [""]).delay(t(1)).take(4)
        prop.sampledBy(stream)
      [1, 2, 1, 2])
  describe "accepts optional combinator function f(Vp, Vs)", ->
    expectStreamEvents(
      ->
        prop = series(2, ["a", "b"]).toProperty()
        stream = series(2, ["1", "2", "1", "2"]).delay(t(1))
        prop.sampledBy(stream, add)
      ["a1", "b2", "b1", "b2"])
  describe "allows method name instead of function too", ->
    expectStreamEvents(
      ->
        Bacon.constant([1]).sampledBy(Bacon.once([2]), ".concat")
      [[1, 2]])
  describe "works with same origin", ->
    expectStreamEvents(
      ->
        src = series(2, [1, 2])
        src.toProperty().sampledBy(src)
      [1, 2])
    expectStreamEvents(
      ->
        src = series(2, [1, 2])
        src.toProperty().sampledBy(src.map(times, 2))
      [1, 2])
  describe "uses updated property after combine", ->
    latter = (a, b) -> b
    expectPropertyEvents(
      ->
        src = series(2, ["b", "c"]).toProperty("a")
        combined = Bacon.constant().combine(src, latter)
        src.sampledBy(combined, add)
      ["aa", "bb", "cc"])
  describe "uses updated property after combine with subscriber", ->
    latter = (a, b) -> b
    expectPropertyEvents(
      ->
        src = series(2, ["b", "c"]).toProperty("a")
        combined = Bacon.constant().combine(src, latter)
        combined.onValue(->)
        src.sampledBy(combined, add)
      ["aa", "bb", "cc"])
  describe "skips samplings that occur before the property gets its first value", ->
    expectStreamEvents(
      ->
        p = series(5, [1]).toProperty()
        p.sampledBy(series(3, [0]))
      [])
    expectStreamEvents(
      -> 
        p = series(5, [1, 2]).toProperty()
        p.sampledBy(series(3, [0, 0, 0, 0]))
      [1, 1, 2])
    expectPropertyEvents(
      -> 
        p = series(5, [1, 2]).toProperty()
        p.sampledBy(series(3, [0, 0, 0, 0]).toProperty())
      [1, 1, 2])
  describe "works with stream of functions", ->
    f = ->
    expectStreamEvents(
      ->
        p = series(1, [f]).toProperty()
        p.sampledBy(series(1, [1, 2, 3]))
      [f, f, f])
  describe "works with synchronous sampler stream", ->
    expectStreamEvents(
      -> Bacon.constant(1).sampledBy(Bacon.fromArray([1,2,3]))
      [1,1,1])
    expectStreamEvents(
      -> Bacon.later(1, 1).toProperty().sampledBy(Bacon.fromArray([1,2,3]))
      [])
  describe "laziness", ->
    calls = 0
    id = (x) -> 
      calls++
      x
    sampler = Bacon.later(5)
    property = repeat(1, [1]).toProperty().map(id)
    sampled = property.sampledBy sampler
    sampled.onValue()
    before (done) ->
      sampled.onEnd(done)
    it "preserves laziness", ->
      expect(calls).to.equal(1)

describe "Property.sampledBy(property)", ->
  describe "samples property at events, resulting to a Property", ->
    expectPropertyEvents(
      ->
        prop = series(2, [1, 2]).toProperty()
        sampler = repeat(3, ["troll"]).take(4).toProperty()
        prop.sampledBy(sampler)
      [1, 2, 2, 2])
  describe "accepts optional combinator function f(Vp, Vs)", ->
    expectPropertyEvents(
      ->
        prop = series(2, ["a", "b"]).toProperty()
        sampler = series(2, ["1", "2", "1", "2"]).delay(t(1)).toProperty()
        prop.sampledBy(sampler, add)
      ["a1", "b2", "b1", "b2"])

describe "Property.sample", ->
  describe "samples property by given interval", ->
    expectStreamEvents(
      ->
        prop = series(2, [1, 2]).toProperty()
        prop.sample(t(3)).take(4)
      [1, 2, 2, 2])
  describe "includes all errors", ->
    expectStreamEvents(
      ->
        prop = series(2, [1, error(), 2]).toProperty()
        prop.sample(t(5)).take(2)
      [error(), 1, 2])
  describe "works with synchronous source", ->
    expectStreamEvents(
      ->
        prop = Bacon.constant(1)
        prop.sample(t(3)).take(4)
      [1, 1, 1, 1])

describe "EventStream.scan", ->
  describe "accumulates values with given seed and accumulator function, passing through errors", ->
    expectPropertyEvents(
      -> series(1, [1, 2, error(), 3]).scan(0, add)
      [0, 1, 3, error(), 6])
  describe "also works with method name", ->
    expectPropertyEvents(
      -> series(1, [[1], [2]]).scan([], ".concat")
      [[], [1], [1, 2]])
  it "yields the seed value immediately", ->
    outputs = []
    bus = new Bacon.Bus()
    bus.scan(0, -> 1).onValue((value) -> outputs.push(value))
    expect(outputs).to.deep.equal([0])
  describe "yields null seed value", ->
    expectPropertyEvents(
      -> series(1, [1]).scan(null, ->1)
      [null, 1])
  describe "works with synchronous streams", ->
    expectPropertyEvents(
      -> Bacon.fromArray([1,2,3]).scan(0, ((x,y)->x+y))
      [0,1,3,6])

describe "EventStream.fold", ->
  describe "folds stream into a single-valued Property, passes through errors", ->
    expectPropertyEvents(
      -> series(1, [1, 2, error(), 3]).fold(0, add)
      [error(), 6])
  describe "has reduce as synonym", ->
    expectPropertyEvents(
      -> series(1, [1, 2, error(), 3]).fold(0, add)
      [error(), 6])
  describe "works with synchronous source", ->
    expectPropertyEvents(
      -> Bacon.fromArray([1, 2, error(), 3]).fold(0, add)
      [error(), 6])

describe "Property.scan", ->
  describe "with Init value, starts with f(seed, init)", ->
    expectPropertyEvents(
      -> series(1, [2,3]).toProperty(1).scan(0, add)
      [1, 3, 6])
  describe "without Init value, starts with seed", ->
    expectPropertyEvents(
      -> series(1, [2,3]).toProperty().scan(0, add)
      [0, 2, 5])
  describe "treats null seed value like any other value", ->
    expectPropertyEvents(
      -> series(1, [1]).toProperty().scan(null, add)
      [null, 1])
    expectPropertyEvents(
      -> series(1, [2]).toProperty(1).scan(null, add)
      [1, 3])
  describe "for synchronous source", ->
    describe "with Init value, starts with f(seed, init)", ->
      expectPropertyEvents(
        -> Bacon.fromArray([2,3]).toProperty(1).scan(0, add)
        [1, 3, 6])
    describe "without Init value, starts with seed", ->
      expectPropertyEvents(
        -> Bacon.fromArray([2,3]).toProperty().scan(0, add)
        [0, 2, 5])
    describe "works with synchronously responding empty source", ->
      expectPropertyEvents(
        -> Bacon.never().toProperty(1).scan(0, add)
        [1])

describe "EventStream.withStateMachine", ->
  f = (sum, event) ->
    if event.hasValue()
      [sum + event.value(), []]
    else if event.isEnd()
      [sum, [new Bacon.Next(-> sum), event]]
    else
      [sum, [event]]
  describe "runs state machine on the stream", ->
    expectStreamEvents(
      -> Bacon.fromArray([1,2,3]).withStateMachine(0, f)
      [6])

describe "Property.withStateMachine", ->
  describe "runs state machine on the stream", ->
    expectPropertyEvents(
      -> Bacon.fromArray([1,2,3]).toProperty().withStateMachine(0, (sum, event) ->
        if event.hasValue()
          [sum + event.value(), []]
        else if event.isEnd()
          [sum, [new Bacon.Next(-> sum), event]]
        else
          [sum, [event]])
      [6])

describe "Property.fold", ->
  describe "Folds Property into a single-valued one", ->
    expectPropertyEvents(
      -> series(1, [2,3]).toProperty(1).fold(0, add)
      [6])

describe "EventStream.diff", ->
  describe "apply diff function to previous and current values, passing through errors", ->
    expectPropertyEvents(
      -> series(1, [1, 2, error(), 3]).diff(0, add)
      [1, 3, error(), 5])
  describe "also works with method name", ->
    expectPropertyEvents(
      -> series(1, [[1], [2]]).diff([0], ".concat")
      [[0, 1], [1, 2]])
  it "does not yields the start value immediately", ->
    outputs = []
    bus = new Bacon.Bus()
    bus.diff(0, -> 1).onValue((value) -> outputs.push(value))
    expect(outputs).to.deep.equal([])

describe "Property.diff", ->
  describe "with Init value, starts with f(start, init)", ->
    expectPropertyEvents(
      -> series(1, [2,3]).toProperty(1).diff(0, add)
      [1, 3, 5])
  describe "without Init value, waits for the first value", ->
    expectPropertyEvents(
      -> series(1, [2,3]).toProperty().diff(0, add)
      [2, 5])
  describe "treats null start value like any other value", ->
    expectPropertyEvents(
      -> series(1, [1]).toProperty().diff(null, add)
      [1])
    expectPropertyEvents(
      -> series(1, [2]).toProperty(1).diff(null, add)
      [1, 3])

describe "EventStream.zip", ->
  describe "pairwise combines values from two streams", ->
    expectStreamEvents(
      -> series(1, [1, 2, 3]).zip(series(1, ['a', 'b', 'c']))
      [[1, 'a'], [2, 'b'], [3, 'c']])
  describe "passes through errors", ->
    expectStreamEvents(
      -> series(2, [1, error(), 2]).zip(series(2, ['a', 'b']).delay(1))
      [[1, 'a'], error(), [2, 'b']])
  describe "completes as soon as possible", ->
    expectStreamEvents(
      -> series(1, [1]).zip(series(1, ['a', 'b', 'c']))
      [[1, 'a']])
  describe "can zip an observable with itself", ->
    expectStreamEvents(
      ->
        obs = series(1, ['a', 'b', 'c'])
        obs.zip(obs.skip(1))
      [['a', 'b'], ['b', 'c']])

describe "Bacon.zipAsArray", ->
  describe "zips an array of streams into a stream of arrays", ->
    expectStreamEvents(
      ->
        obs = series(1, [1, 2, 3, 4])
        Bacon.zipAsArray([obs, obs.skip(1), obs.skip(2)])
    [[1 , 2 , 3], [2 , 3 , 4]])
  describe "supports n-ary syntax", ->
    expectStreamEvents(
      ->
        obs = series(1, [1, 2, 3, 4])
        Bacon.zipAsArray(obs, obs.skip(1))
    [[1 , 2], [2 , 3], [3, 4]])
  describe "does not synchronize on properties", ->
    expectStreamEvents(
      ->
        obs = series(1, [1, 2, 3, 4])
        Bacon.zipAsArray(obs, obs.skip(1), Bacon.constant(5))
    [[1 , 2, 5], [2 , 3, 5], [3, 4, 5]])

describe "Bacon.zipWith", ->
  describe "zips an array of streams with given function", ->
    expectStreamEvents(
      ->
        obs = series(1, [1, 2, 3, 4])
        Bacon.zipWith([obs, obs.skip(1), obs.skip(2)], ((x,y,z) -> (x + y + z)))
    [1 + 2 + 3, 2 + 3 + 4])
  describe "supports n-ary syntax", ->
    expectStreamEvents(
      ->
        obs = series(1, [1, 2, 3, 4])
        f = ((x,y,z) -> (x + y + z))
        Bacon.zipWith(f, obs, obs.skip(1), obs.skip(2))
    [1 + 2 + 3, 2 + 3 + 4])

describe "Bacon.when", ->
  describe "synchronizes on join patterns", ->
    expectStreamEvents(
      ->
        [a,b,_] = ['a','b','_']
        as = series(1, [a, _, a, a, _, a, _, _, a, a]).filter((x) -> x == a)
        bs = series(1, [_, b, _, _, b, _, b, b, _, _]).filter((x) -> x == b)
        Bacon.when(
          [as, bs], (a,b) ->  a + b,
          [as],     (a)   ->  a)
      ['a', 'ab', 'a', 'ab', 'ab', 'ab'])
  describe "consider the join patterns from top to bottom", ->
    expectStreamEvents(
      ->
        [a,b,_] = ['a','b','_']
        as = series(1, [a, _, a, a, _, a, _, _, a, a]).filter((x) -> x == a)
        bs = series(1, [_, b, _, _, b, _, b, b, _, _]).filter((x) -> x == b)
        Bacon.when(
          [as],     (a)   ->  a,
          [as, bs], (a,b) ->  a + b)
      ['a', 'a', 'a', 'a', 'a', 'a'])
  describe "handles any number of join patterns", ->
    expectStreamEvents(
      ->
        [a,b,c,_] = ['a','b','c','_']
        as = series(1, [a, _, a, _, a, _, a, _, _, _, a, a]).filter((x) -> x == a)
        bs = series(1, [_, b, _, _, _, b, _, b, _, b, _, _]).filter((x) -> x == b)
        cs = series(1, [_, _, _, c, _, _, _, _, c, _, _, _]).filter((x) -> x == c)
        Bacon.when(
          [as, bs, cs], (a,b,c) ->  a + b + c,
          [as, bs],     (a,b) ->  a + b,
          [as],         (a)   ->  a)
      ['a', 'ab', 'a', 'abc', 'abc', 'ab'])
  describe "does'nt synchronize on properties", ->
    expectStreamEvents(
      ->
        p = repeat(1, ["p"]).take(100).toProperty()
        s = series(3, ["1", "2", "3"])
        Bacon.when(
          [p,s], (p, s) -> p + s)
      ["p1", "p2", "p3"])
    expectStreamEvents(
      ->
        p = series(3, ["p"]).toProperty()
        s = series(1, ["1"])
        Bacon.when(
          [p,s], (p, s) -> p + s)
      [])
    expectStreamEvents(
      ->
        p = repeat(1, ["p"]).take(100).toProperty()
        s = series(3, ["1", "2", "3"]).toProperty()
        Bacon.when(
          [p,s], (p, s) -> p + s)
      [])
    expectStreamEvents(
      ->
        [a,b,c,_] = ['a','b','c','_']
        as = series(1, [a, _, a, _, a, _, a, _, _, _, a, _, a]).filter((x) -> x == a)
        bs = series(1, [_, b, _, _, _, b, _, b, _, b, _, _, _]).filter((x) -> x == b)
        cs = series(1, [_, _, _, c, _, _, _, _, c, _, _, c, _]).filter((x) -> x == c).map(1).scan 0, ((x,y) -> x + y)
        Bacon.when(
          [as, bs, cs], (a,b,c) ->  a + b + c,
          [as],         (a)   ->  a)
      ['a', 'ab0', 'a', 'ab1', 'ab2', 'ab3'])
  describe "returns Bacon.never() on the empty list of patterns", ->
    expectStreamEvents(
      ->
        Bacon.when()
      [])
  describe "works with single stream", ->
    expectStreamEvents(
      -> Bacon.when([Bacon.once(1)], (x) -> x)
      [1])
  describe "works with multiples of streams", ->
    expectStreamEvents(
      -> 
        [h,o,c,_] = ['h','o','c','_']
        hs = series(1, [h, _, h, _, h, _, h, _, _, _, h, _, h]).filter((x) -> x == h)
        os = series(1, [_, o, _, _, _, o, _, o, _, o, _, _, _]).filter((x) -> x == o)
        cs = series(1, [_, _, _, c, _, _, _, _, c, _, _, c, _]).filter((x) -> x == c)
        Bacon.when(
          [hs, hs, os], (h1,h2,o) ->  [h1,h2,o],
          [cs, os],    (c,o) -> [c,o])
      [['h', 'h', 'o'], ['c', 'o'], ['h', 'h', 'o'], ['c', 'o']])
  describe "works with multiples of properties", ->
    expectStreamEvents(
      ->
        c = Bacon.constant("c")
        Bacon.when(
          [c, c, Bacon.once(1)], (c1, c2, _) -> c1 + c2)
      ["cc"])
  describe "accepts constants instead of functions too", ->
    expectStreamEvents(
      -> Bacon.when(Bacon.once(1), 2)
      [2])
  describe "works with synchronous sources", ->
    expectStreamEvents(
      ->
        xs = Bacon.once "x"
        ys = Bacon.once "y"
        Bacon.when(
          [xs, ys], (x, y) -> x + y
        )
      ["xy"])

describe "Bacon.update", ->
  describe "works like Bacon.when, but produces a property, and can be defined in terms of a current value", ->
    expectPropertyEvents(
      ->
        [r,i,_] = ['r','i',0]
        incr  = series(1, [1, _, 1, _, 2, _, 1, _, _, _, 2, _, 1]).filter((x) -> x != _)
        reset = series(1, [_, r, _, _, _, r, _, r, _, r, _, _, _]).filter((x) -> x == r)
        Bacon.update(
          0,
          [reset], 0,
          [incr], (i,c) -> i+c)
      [0, 1, 0, 1, 3, 0, 1, 0, 0, 2, 3])

  describe "Correctly handles multiple arguments in parameter list, and synchronous sources", ->
    expectPropertyEvents(
      ->
        one = Bacon.once(1)
        two = Bacon.once(2)
        Bacon.update(
          0,
          [one, two],  (i, a, b) -> [i,a,b])
      [0, [0,1,2]])

describe "combineTemplate", ->
  describe "combines streams according to a template object", ->
    expectPropertyEvents(
      ->
         firstName = Bacon.constant("juha")
         lastName = Bacon.constant("paananen")
         userName = Bacon.constant("mr.bacon")
         Bacon.combineTemplate({ userName: userName, password: "*****", fullName: { firstName: firstName, lastName: lastName }})
      [{ userName: "mr.bacon", password: "*****", fullName: { firstName: "juha", lastName: "paananen" } }])
  describe "works with a single-stream template", ->
    expectPropertyEvents(
      ->
        bacon = Bacon.constant("bacon")
        Bacon.combineTemplate({ favoriteFood: bacon })
      [{ favoriteFood: "bacon" }])
  describe "works when dynamic part is not the last part (bug fix)", ->
    expectPropertyEvents(
      ->
        username = Bacon.constant("raimohanska")
        password = Bacon.constant("easy")
        Bacon.combineTemplate({url: "/user/login",
        data: { username: username, password: password }, type: "post"})
      [url: "/user/login", data: {username: "raimohanska", password: "easy"}, type: "post"])
  describe "works with arrays as data (bug fix)", ->
    expectPropertyEvents(
      -> Bacon.combineTemplate( { x : Bacon.constant([]), y : Bacon.constant([[]]), z : Bacon.constant(["z"])})
      [{ x : [], y : [[]], z : ["z"]}])
  describe "supports empty object", ->
    expectPropertyEvents(
      -> Bacon.combineTemplate({})
      [{}])
  it "supports arrays", ->
    value = {key: [{ x: 1 }, { x: 2 }]}
    Bacon.combineTemplate(value).onValue (x) ->
      expect(x).to.deep.equal(value)
      expect(x.key instanceof Array).to.deep.equal(true) # seems that the former passes even if x is not an array
    value = [{ x: 1 }, { x: 2 }]
    Bacon.combineTemplate(value).onValue (x) ->
      expect(x).to.deep.equal(value)
      expect(x instanceof Array).to.deep.equal(true)
    value = {key: [{ x: 1 }, { x: 2 }], key2: {}}
    Bacon.combineTemplate(value).onValue (x) ->
      expect(x).to.deep.equal(value)
      expect(x.key instanceof Array).to.deep.equal(true)
    value = {key: [{ x: 1 }, { x: Bacon.constant(2) }]}
    Bacon.combineTemplate(value).onValue (x) ->
      expect(x).to.deep.equal({key: [{ x: 1 }, { x: 2 }]})
      expect(x.key instanceof Array).to.deep.equal(true) # seems that the former passes even if x is not an array
  it "supports nulls", ->
    value = {key: null}
    Bacon.combineTemplate(value).onValue (x) ->
      expect(x).to.deep.equal(value)
  it "supports NaNs", ->
    value = {key: NaN}
    Bacon.combineTemplate(value).onValue (x) ->
      expect(isNaN(x.key)).to.deep.equal(true)
  it "supports dates", ->
    value = {key: new Date()}
    Bacon.combineTemplate(value).onValue (x) ->
      expect(x).to.deep.equal(value)
  it "supports regexps", ->
    value = {key: /[0-0]/i}
    Bacon.combineTemplate(value).onValue (x) ->
      expect(x).to.deep.equal(value)
  it "supports functions", ->
    value = {key: ->}
    Bacon.combineTemplate(value).onValue (x) ->
      expect(x).to.deep.equal(value)

describe "Property.decode", ->
  describe "switches between source Properties based on property value", ->
    expectPropertyEvents(
      ->
        a = Bacon.constant("a")
        b = Bacon.constant("b")
        c = Bacon.constant("c")
        series(1, [1,2,3]).toProperty().decode({1: a, 2: b, 3: c})
      ["a", "b", "c"])

describe "EventStream.decode", ->
  describe "switches between source Properties based on property value", ->
    expectPropertyEvents(
      ->
        a = Bacon.constant("a")
        b = Bacon.constant("b")
        c = Bacon.constant("c")
        series(1, [1,2,3]).decode({1: a, 2: b, 3: c})
      ["a", "b", "c"])

describe "Observable.onValues", ->
  it "splits value array to callback arguments", ->
    f = mockFunction()
    Bacon.constant([1,2,3]).onValues(f)
    f.verify(1,2,3)

describe "Bacon.onValues", ->
  it "is a shorthand for combineAsArray.onValues", ->
    f = mockFunction()
    Bacon.onValues(1, 2, 3, f)
    f.verify(1,2,3)

describe "Observable.subscribe and onValue", ->
  it "returns a dispose() for unsubscribing", ->
    s = new Bacon.Bus()
    values = []
    dispose = s.onValue (value) -> values.push value
    s.push "lol"
    dispose()
    s.push "wut"
    expect(values).to.deep.equal(["lol"])

describe "Observable.onEnd", ->
  it "is called on stream end", ->
    s = new Bacon.Bus()
    ended = false
    s.onEnd(-> ended = true)
    s.push("LOL")
    expect(ended).to.deep.equal(false)
    s.end()
    expect(ended).to.deep.equal(true)

describe "Field value extraction", ->
  describe "extracts field value", ->
    expectStreamEvents(
      -> Bacon.once({lol:"wut"}).map(".lol")
      ["wut"])
  describe "extracts nested field value", ->
    expectStreamEvents(
      -> Bacon.once({lol:{wut: "wat"}}).map(".lol.wut")
      ["wat"])
  describe "yields 'undefined' if any value on the path is 'undefined'", ->
    expectStreamEvents(
      -> Bacon.once({}).map(".lol.wut")
      [undefined])
  it "if field value is method, it does a method call", ->
    context = null
    result = null
    object = {
      method: ->
        context = this
        "result"
    }
    Bacon.once(object).map(".method").onValue((x) -> result = x)
    expect(result).to.deep.equal("result")
    expect(context).to.deep.equal(object)

testSideEffects = (wrapper, method) ->
  ->
    it "(f) calls function with property value", ->
      f = mockFunction()
      wrapper("kaboom")[method](f)
      f.verify("kaboom")
    it "(f, param) calls function, partially applied with param", ->
      f = mockFunction()
      wrapper("kaboom")[method](f, "pow")
      f.verify("pow", "kaboom")
    it "('.method') calls event value object method", ->
      value = mock("get")
      value.when().get().thenReturn("pow")
      wrapper(value)[method](".get")
      value.verify().get()
    it "('.method', param) calls event value object method with param", ->
      value = mock("get")
      value.when().get("value").thenReturn("pow")
      wrapper(value)[method](".get", "value")
      value.verify().get("value")
    it "(object, method) calls object method with property value", ->
      target = mock("pow")
      wrapper("kaboom")[method](target, "pow")
      target.verify().pow("kaboom")
    it "(object, method, param) partially applies object method with param", ->
      target = mock("pow")
      wrapper("kaboom")[method](target, "pow", "smack")
      target.verify().pow("smack", "kaboom")
    it "(object, method, param1, param2) partially applies with 2 args", ->
      target = mock("pow")
      wrapper("kaboom")[method](target, "pow", "smack", "whack")
      target.verify().pow("smack", "whack", "kaboom")

describe "Property.onValue", testSideEffects(Bacon.constant, "onValue")
describe "Property.assign", testSideEffects(Bacon.constant, "assign")
describe "EventStream.onValue", testSideEffects(Bacon.once, "onValue")

describe "Property.assign", ->
  it "calls given objects given method with property values", ->
    target = mock("pow")
    Bacon.constant("kaboom").assign(target, "pow")
    target.verify().pow("kaboom")
  it "allows partial application of method (i.e. adding fixed args)", ->
    target = mock("pow")
    Bacon.constant("kaboom").assign(target, "pow", "smack")
    target.verify().pow("smack", "kaboom")
  it "allows partial application of method with 2 args (i.e. adding fixed args)", ->
    target = mock("pow")
    Bacon.constant("kaboom").assign(target, "pow", "smack", "whack")
    target.verify().pow("smack", "whack", "kaboom")

describe "Bacon.Bus", ->
  it "merges plugged-in streams", ->
    bus = new Bacon.Bus()
    values = []
    dispose = bus.onValue (value) -> values.push value
    push = new Bacon.Bus()
    bus.plug(push)
    push.push("lol")
    expect(values).to.deep.equal(["lol"])
    dispose()
    verifyCleanup()
  describe "works with looped streams", ->
    expectStreamEvents(
      ->
        bus = new Bacon.Bus()
        bus.plug(Bacon.later(t(2), "lol"))
        bus.plug(bus.filter((value) => "lol" == value).map(=> "wut"))
        Bacon.later(t(4)).onValue(=> bus.end())
        bus
      ["lol", "wut"])
  it "dispose works with looped streams", ->
    bus = new Bacon.Bus()
    bus.plug(Bacon.later(t(2), "lol"))
    bus.plug(bus.filter((value) => "lol" == value).map(=> "wut"))
    dispose = bus.onValue(=>)
    dispose()
  it "Removes input from input list on End event", ->
    subscribed = 0
    bus = new Bacon.Bus()
    input = new Bacon.Bus()
    # override subscribe to increase the subscribed-count
    inputSubscribe = input.subscribe
    input.subscribe = (sink) ->
      subscribed++
      inputSubscribe(sink)
    bus.plug(input)
    dispose = bus.onValue(=>)
    input.end()
    dispose()
    bus.onValue(=>) # this latter subscription should not go to the ended source anymore
    expect(subscribed).to.deep.equal(1)
  it "unsubscribes inputs on end() call", ->
    bus = new Bacon.Bus()
    input = new Bacon.Bus()
    events = []
    bus.plug(input)
    bus.subscribe((e) => events.push(e))
    input.push("a")
    bus.end()
    input.push("b")
    expect(toValues(events)).to.deep.equal(["a", "<end>"])
  it "handles cold single-event streams correctly (bug fix)", ->
    values = []
    bus = new Bacon.Bus()
    bus.plug(Bacon.once("x"))
    bus.plug(Bacon.once("y"))
    bus.onValue((x) -> values.push(x))
    expect(values).to.deep.equal(["x", "y"])

  it "handles end() calls even when there are no subscribers", ->
    bus = new Bacon.Bus()
    bus.end()

  describe "delivers pushed events and errors", ->
    expectStreamEvents(
      ->
        s = new Bacon.Bus()
        s.push "pullMe"
        soon ->
          s.push "pushMe"
          s.error()
          s.end()
        s
      ["pushMe", error()])

  it "does not deliver pushed events after end() call", ->
    called = false
    bus = new Bacon.Bus()
    bus.onValue(-> called = true)
    bus.end()
    bus.push("LOL")
    expect(called).to.deep.equal(false)

  it "does not plug after end() call", ->
    plugged = false
    bus = new Bacon.Bus()
    bus.end()
    bus.plug(new Bacon.EventStream((sink) -> plugged = true; (->)))
    bus.onValue(->)
    expect(plugged).to.deep.equal(false)

  it "returns unplug function from plug", ->
    values = []
    bus = new Bacon.Bus()
    src = new Bacon.Bus()
    unplug = bus.plug(src)
    bus.onValue((x) -> values.push(x))
    src.push("x")
    unplug()
    src.push("y")
    expect(values).to.deep.equal(["x"])

  it "allows consumers to re-subscribe after other consumers have unsubscribed (bug fix)", ->
    bus = new Bacon.Bus
    otherBus = new Bacon.Bus
    otherBus.plug(bus)
    unsub = otherBus.onValue ->
    unsub()
    o = []
    otherBus.onValue (v) -> o.push(v)
    bus.push("foo")
    expect(o).to.deep.equal(["foo"])


describe "EventStream", ->
  describe "works with functions as values (bug fix)", ->
    expectStreamEvents(
      -> Bacon.once(-> "hello").map((f) -> f())
      ["hello"])
    expectStreamEvents(
      -> Bacon.once(-> "hello").flatMap(Bacon.once).map((f) -> f())
      ["hello"])
    expectPropertyEvents(
      -> Bacon.constant(-> "hello").map((f) -> f())
      ["hello"])
    expectStreamEvents(
      -> Bacon.constant(-> "hello").flatMap(Bacon.once).map((f) -> f())
      ["hello"])
  it "handles one subscriber added twice just like two separate subscribers (case Bacon.noMore)", ->
    values = []
    bus = new Bacon.Bus()
    f = (v) ->
      if v.hasValue()
        values.push(v.value())
        return Bacon.noMore
    bus.subscribe(f)
    bus.subscribe(f)
    bus.push("bacon")
    expect(values).to.deep.equal(["bacon", "bacon"])
  it "handles one subscriber added twice just like two separate subscribers (case unsub)", ->
    values = []
    bus = new Bacon.Bus()
    f = (v) ->
      if v.hasValue()
        values.push(v.value())
    bus.subscribe(f)
    unsub = bus.subscribe(f)
    unsub()
    bus.push("bacon")
    expect(values).to.deep.equal(["bacon"])

describe "Bacon.fromBinder", ->
  describe "Provides an easier alternative to the EventStream constructor, allowing sending multiple events at a time", ->
    expectStreamEvents(
      -> 
        Bacon.fromBinder (sink) ->
          sink([new Bacon.Next(1), new Bacon.End()])
          (->)
      [1])
  describe "Allows sending unwrapped values", ->
    expectStreamEvents(
      -> 
        Bacon.fromBinder (sink) ->
          sink([1, new Bacon.End()])
          (->)
      [1])
  describe "Allows sending single value without wrapping array", ->
    expectStreamEvents(
      -> 
        Bacon.fromBinder (sink) ->
          sink(1)
          sink(new Bacon.End())
          (->)
      [1])

describe "Infinite synchronous sequences", ->
  describe "Limiting length with take(n)", ->
    expectStreamEvents(
      -> endlessly(1,2,3).take(4)
      [1,2,3,1])
    expectStreamEvents(
      -> endlessly(1,2,3).take(4).concat(Bacon.once(5))
      [1,2,3,1,5])
    expectStreamEvents(
      -> endlessly(1,2,3).take(4).concat(endlessly(5, 6).take(2))
      [1,2,3,1,5,6])
  describe "With flatMap", ->
    expectStreamEvents(
      -> Bacon.fromArray([1,2]).flatMap((x) -> endlessly(x)).take(2)
      [1,1])
    expectStreamEvents(
      -> endlessly(1,2).flatMap((x) -> endlessly(x)).take(2)
      [1,1])

endlessly = (values...) ->
  index = 0
  Bacon.fromSynchronousGenerator -> new Bacon.Next(-> values[index++ % values.length])

Bacon.fromGenerator = (generator) ->
  Bacon.fromBinder (sink) ->
    unsubd = false
    push = (events) ->
      events = Bacon._.toArray(events)
      for event in events
        return if unsubd
        reply = sink event
        return if event.isEnd() or reply == Bacon.noMore
      generator(push)
    push []
    -> unsubd = true

Bacon.fromSynchronousGenerator = (generator) ->
  Bacon.fromGenerator (push) ->
    push generator()

lessThan = (limit) ->
  (x) -> x < limit
times = (x, y) -> x * y
add = (x, y) -> x + y
id = (x) -> x

