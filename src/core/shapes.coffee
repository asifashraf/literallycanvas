util = require './util'
lineEndCapShapes = require '../core/lineEndCapShapes.coffee'
TextRenderer = require './TextRenderer'

shapes = {}


defineShape = (name, props) ->
  Shape = (args...) ->
    props.constructor.call(this, args...)
    this
  props.toSVG ?= -> ''
  Shape.prototype.className = name
  Shape.fromJSON = props.fromJSON
  Shape.prototype.drawLatest = (ctx, bufferCtx) -> @draw(ctx, bufferCtx)

  for k of props
    if k != 'fromJSON'
      Shape.prototype[k] = props[k]

  shapes[name] = Shape
  Shape


createShape = (name, args...) ->
  s = new shapes[name](args...)
  s.id = util.getGUID()
  s


JSONToShape = ({className, data, id}) ->
  if className of shapes
    shape = shapes[className].fromJSON(data)
    if shape
      shape.id = id if id
      return shape
    else
      console.log 'Unreadable shape:', className, data
      return null
  else
    console.log "Unknown shape:", className, data
    return null


shapeToJSON = (shape) ->
  {className: shape.className, data: shape.toJSON(), id: shape.id}


# this fn depends on Point, but LinePathShape depends on it, so it can't be
# moved out of this file yet.
bspline = (points, order) ->
  if not order
    return points
  return bspline(_dual(_dual(_refine(points))), order - 1)

_refine = (points) ->
  points = [points[0]].concat(points).concat(util.last(points))
  refined = []

  index = 0
  for point in points
    refined[index * 2] = point
    refined[index * 2 + 1] = _mid point, points[index + 1] if points[index + 1]
    index += 1

  return refined

_dual = (points) ->
  dualed = []

  index = 0
  for point in points
    dualed[index] = _mid point, points[index + 1] if points[index + 1]
    index += 1

  return dualed

_mid = (a, b) ->
  createShape('Point', {
    x: a.x + ((b.x - a.x) / 2),
    y: a.y + ((b.y - a.y) / 2),
    size: a.size + ((b.size - a.size) / 2),
    color: a.color
  })


defineShape 'Image',
  # TODO: allow resizing/filling
  constructor: (args={}) ->
    @x = args.x or 0
    @y = args.y or 0
    @image = args.image or null
  draw: (ctx, retryCallback) ->
    if @image.width
      ctx.drawImage(@image, @x, @y)
    else if retryCallback
      @image.onload = retryCallback
  getBoundingRect: -> {@x, @y, width: @image.width, height: @image.height}
  toJSON: -> {@x, @y, imageSrc: @image.src}
  fromJSON: (data) ->
    img = new Image()
    img.src = data.imageSrc
    createShape('Image', {x: data.x, x: data.y, image: img})

  toSVG: ->
    "
      <image x='#{@x}' y='#{@y}'
        width='#{@image.naturalWidth}' height='#{@image.naturalHeight}'
        xlink:href='#{@image.src}' />
    "


defineShape 'Rectangle',
  constructor: (args={}) ->
    @x = args.x or 0
    @y = args.y or 0
    @width = args.width or 0
    @height = args.height or 0
    @strokeWidth = args.strokeWidth or 1
    @strokeColor = args.strokeColor or 'black'
    @fillColor = args.fillColor or 'transparent'

  draw: (ctx) ->
    ctx.fillStyle = @fillColor
    ctx.fillRect(@x, @y, @width, @height)
    ctx.lineWidth = @strokeWidth
    ctx.strokeStyle = @strokeColor
    ctx.strokeRect(@x, @y, @width, @height)

  getBoundingRect: -> {
    x: @x - @strokeWidth / 2,
    y: @y - @strokeWidth / 2,
    width: @width + @strokeWidth,
    height: @height + @strokeWidth,
  }
  toJSON: -> {@x, @y, @width, @height, @strokeWidth, @strokeColor, @fillColor}
  fromJSON: (data) -> createShape('Rectangle', data)

  toSVG: ->
    "
      <rect x='#{@x}' y='#{@y}' width='#{@width}' height='#{@height}'
        stroke='#{@strokeColor}' fill='#{@fillColor}'
        stroke-width='#{@strokeWidth}' />
    "


# this is pretty similar to the Rectangle shape. maybe consolidate somehow.
defineShape 'Ellipse',
  constructor: (args={}) ->
    @x = args.x or 0
    @y = args.y or 0
    @width = args.width or 0
    @height = args.height or 0
    @strokeWidth = args.strokeWidth or 1
    @strokeColor = args.strokeColor or 'black'
    @fillColor = args.fillColor or 'transparent'

  draw: (ctx) ->
    ctx.save()
    halfWidth = Math.floor(@width / 2)
    halfHeight = Math.floor(@height / 2)
    centerX = @x + halfWidth
    centerY = @y + halfHeight

    ctx.translate(centerX, centerY)
    ctx.scale(1, Math.abs(@height / @width))
    ctx.beginPath()
    ctx.arc(0, 0, Math.abs(halfWidth), 0, Math.PI * 2)
    ctx.closePath()
    ctx.restore()

    ctx.fillStyle = @fillColor
    ctx.fill()
    ctx.lineWidth = @strokeWidth
    ctx.strokeStyle = @strokeColor
    ctx.stroke()

  getBoundingRect: -> {
    x: @x - @strokeWidth / 2,
    y: @y - @strokeWidth / 2,
    width: @width + @strokeWidth,
    height: @height + @strokeWidth,
  }
  toJSON: -> {@x, @y, @width, @height, @strokeWidth, @strokeColor, @fillColor}
  fromJSON: (data) -> createShape('Ellipse', data)

  toSVG: ->
    halfWidth = Math.floor(@width / 2)
    halfHeight = Math.floor(@height / 2)
    centerX = @x + halfWidth
    centerY = @y + halfHeight
    "
      <ellipse cx='#{centerX}' cy='#{centerY}' rx='#{halfWidth}'
        ry='#{halfHeight}'
        stroke='#{@strokeColor}' fill='#{@fillColor}'
        stroke-width='#{@strokeWidth}' />
    "


defineShape 'Line',
  constructor: (args={}) ->
    @x1 = args.x1 or 0
    @y1 = args.y1 or 0
    @x2 = args.x2 or 0
    @y2 = args.y2 or 0
    @strokeWidth = args.strokeWidth or 1
    @strokeStyle = args.strokeStyle or null
    @color = args.color or 'black'
    @capStyle = args.capStyle or 'round'
    @endCapShapes = args.endCapShapes or [null, null]
    @dash = args.dash or null

  draw: (ctx) ->
    ctx.lineWidth = @strokeWidth
    ctx.strokeStyle = @color
    ctx.lineCap = @capStyle
    ctx.setLineDash(@dash) if @dash
    ctx.beginPath()
    ctx.moveTo(@x1, @y1)
    ctx.lineTo(@x2, @y2)
    ctx.stroke()
    ctx.setLineDash([]) if @dash

    arrowWidth = Math.max(@strokeWidth * 2.2, 5)
    if @endCapShapes[0]
      lineEndCapShapes[@endCapShapes[0]].drawToCanvas(
        ctx, @x1, @y1, Math.atan2(@y1 - @y2, @x1 - @x2), arrowWidth, @color)
    if @endCapShapes[1]
      lineEndCapShapes[@endCapShapes[1]].drawToCanvas(
        ctx, @x2, @y2, Math.atan2(@y2 - @y1, @x2 - @x1), arrowWidth, @color)

  getBoundingRect: -> {
    x: Math.min(@x1, @x2) - @strokeWidth / 2,
    y: Math.min(@y1, @y2) - @strokeWidth / 2,
    width: Math.abs(@x2 - @x1) + @strokeWidth / 2,
    height: Math.abs(@y2 - @y1) + @strokeWidth / 2,
  }
  toJSON: ->
    {@x1, @y1, @x2, @y2, @strokeWidth, @color, @capStyle, @dash, @endCapShapes}
  fromJSON: (data) -> createShape('Line', data)

  toSVG: ->
    dashString = if @dash then "stroke-dasharray='#{@dash.join(', ')}'" else ''
    capString = ''
    arrowWidth = Math.max(@strokeWidth * 2.2, 5)
    if @endCapShapes[0]
      capString += lineEndCapShapes[@endCapShapes[0]].svg(
        @x1, @y1, Math.atan2(@y1 - @y2, @x1 - @x2), arrowWidth, @color)
    if @endCapShapes[1]
      capString += lineEndCapShapes[@endCapShapes[1]].svg(
        @x2, @y2, Math.atan2(@y2 - @y1, @x2 - @x1), arrowWidth, @color)
    "
      <g>
        <line x1='#{@x1}' y1='#{@y1}' x2='#{@x2}' y2='#{@y2}' #{dashString}
          stroke-linecap='#{@capStyle}'
          stroke='#{@color}'stroke-width='#{@strokeWidth}' />
        #{capString}
      <g>
    "


# returns false if no points because there are no points to share style
_doAllPointsShareStyle = (points) ->
  return false unless points.length
  size = points[0].size
  color = points[0].color
  for point in points
    unless point.size == size and point.color == color
      console.log size, color, point.size, point.color
    return false unless point.size == size and point.color == color
  return true


_createLinePathFromData = (shapeName, data) ->
  points = null
  if data.points
    points = (JSONToShape(pointData) for pointData in data.points)
  else if data.pointCoordinatePairs
    points = (JSONToShape({
      className: 'Point',
      data: {
        x: x, y: y, size: data.pointSize, color: data.pointColor
        smooth: data.smooth
      }
    }) for [x, y] in data.pointCoordinatePairs)

  smoothedPoints = null
  if data.smoothedPointCoordinatePairs
    smoothedPoints = (JSONToShape({
      className: 'Point',
      data: {
        x: x, y: y, size: data.pointSize, color: data.pointColor
        smooth: data.smooth
      }
    }) for [x, y] in data.pointCoordinatePairs)

  return null unless points[0]
  createShape(shapeName, {
    points, smoothedPoints,
    order: data.order, tailSize: data.tailSize, smooth: data.smooth
  })


linePathFuncs =
  constructor: (args={}) ->
    points = args.points or []
    @order = args.order or 3
    @tailSize = args.tailSize or 3
    @smooth = if 'smooth' of args then args.smooth else true

    # The number of smoothed points generated for each point added
    @segmentSize = Math.pow(2, @order)

    # The number of points used to calculate the bspline to the newest point
    @sampleSize = @tailSize + 1

    if args.smoothedPoints
      @points = args.points
      @smoothedPoints = args.smoothedPoints
    else
      @points = []
      for point in points
        @addPoint(point)

  getBoundingRect: ->
    util.getBoundingRect @points.map (p) -> {
      x: p.x - p.size / 2,
      y: p.y - p.size / 2,
      width: p.size,
      height: p.size,
    }

  toJSON: ->
    if _doAllPointsShareStyle(@points)
      {
        @order, @tailSize, @smooth,
        pointCoordinatePairs: ([point.x, point.y] for point in @points),
        smoothedPointCoordinatePairs: (
          [point.x, point.y] for point in @smoothedPoints),
        pointSize: @points[0].size,
        pointColor: @points[0].color
      }
    else
      {@order, @tailSize, @smooth, points: (shapeToJSON(p) for p in @points)}

  fromJSON: (data) -> _createLinePathFromData('LinePath', data)

  toSVG: ->
    "
      <polyline
        fill='none'
        points='#{@smoothedPoints.map((p) -> "#{p.x},#{p.y}").join(' ')}'
        stroke='#{@points[0].color}' stroke-width='#{@points[0].size}' />
    "

  draw: (ctx) ->
    @drawPoints(ctx, @smoothedPoints)

  drawLatest: (ctx, bufferCtx) ->
    @drawPoints(ctx, if @tail then @tail else @smoothedPoints)

    if @tail
      segmentStart = @smoothedPoints.length - @segmentSize * @tailSize
      drawStart = if segmentStart < @segmentSize * 2 then 0 else segmentStart
      drawEnd = segmentStart + @segmentSize + 1
      @drawPoints(bufferCtx, @smoothedPoints.slice(drawStart, drawEnd))

  addPoint: (point) ->
    @points.push(point)

    if !@smooth
      @smoothedPoints = @points
      return

    if not @smoothedPoints or @points.length < @sampleSize
      @smoothedPoints = bspline(@points, @order)
    else
      @tail = util.last(
        bspline(util.last(@points, @sampleSize), @order),
                   @segmentSize * @tailSize)

      # Remove the last @tailSize - 1 segments from @smoothedPoints
      # then concat the tail. This is done because smoothed points
      # close to the end of the path will change as new points are
      # added.
      @smoothedPoints = @smoothedPoints.slice(
        0, @smoothedPoints.length - @segmentSize * (@tailSize - 1)
      ).concat(@tail)

  drawPoints: (ctx, points) ->
    return unless points.length

    ctx.lineCap = 'round'

    ctx.strokeStyle = points[0].color
    ctx.lineWidth = points[0].size

    ctx.beginPath()
    ctx.moveTo(points[0].x, points[0].y)

    for point in points.slice(1)
      ctx.lineTo(point.x, point.y)

    ctx.stroke()


LinePath = defineShape 'LinePath', linePathFuncs


defineShape 'ErasedLinePath',
  constructor: linePathFuncs.constructor
  toJSON: linePathFuncs.toJSON
  addPoint: linePathFuncs.addPoint
  drawPoints: linePathFuncs.drawPoints
  getBoundingRect: linePathFuncs.getBoundingRect

  draw: (ctx) ->
    ctx.save()
    ctx.globalCompositeOperation = "destination-out"
    linePathFuncs.draw.call(this, ctx)
    ctx.restore()

  drawLatest: (ctx, bufferCtx) ->
    ctx.save()
    ctx.globalCompositeOperation = "destination-out"
    bufferCtx.save()
    bufferCtx.globalCompositeOperation = "destination-out"

    linePathFuncs.drawLatest.call(this, ctx, bufferCtx)

    ctx.restore()
    bufferCtx.restore()

  fromJSON: (data) -> _createLinePathFromData('ErasedLinePath', data)


# this is currently just used for LinePath/ErasedLinePath internal storage.
defineShape 'Point',
  constructor: (args={}) ->
    @x = args.x or 0
    @y = args.y or 0
    @size = args.size or 0
    @color = args.color or ''
  lastPoint: -> this
  draw: (ctx) -> throw "not implemented"
  toJSON: -> {@x, @y, @size, @color}
  fromJSON: (data) -> createShape('Point', data)


defineShape 'Text',
  constructor: (args={}) ->
    @x = args.x or 0
    @y = args.y or 0
    @v = args.v or 0  # version (<1 needs position repaired)
    @text = args.text or ''
    @color = args.color or 'black'
    @font  = args.font or '18px sans-serif'
    @forcedWidth = args.forcedWidth or null
    @forcedHeight = args.forcedHeight or null

  _makeRenderer: (ctx) ->
    ctx.lineHeight = 1.2
    @renderer = new TextRenderer(
      ctx, @text, @font, @forcedWidth, @forcedHeight)

    if @v < 1
      console.log 'repairing baseline'
      @v = 1
      @x -= @renderer.metrics.bounds.minx
      @y -= @renderer.metrics.leading - @renderer.metrics.descent

  draw: (ctx, bufferCtx) ->
    @_makeRenderer(ctx) unless @renderer
    ctx.fillStyle = @color
    @renderer.draw(ctx, @x, @y)

  setText: (text) ->
    @text = text
    @renderer = null

  setFont: (font) ->
    @font = font
    @renderer = null

  setPosition: (x, y) ->
    @x = x
    @y = y

  setSize: (forcedWidth, forcedHeight) ->
    @forcedWidth = Math.max(forcedWidth, 0)
    @forcedHeight = Math.max(forcedHeight, 0)
    @renderer = null

  enforceMaxBoundingRect: (lc) ->
    br = @getBoundingRect(lc.ctx)
    lcBoundingRect = {
      x: -lc.position.x / lc.scale,
      y: -lc.position.y / lc.scale,
      width: lc.canvas.width / lc.scale,
      height: lc.canvas.height / lc.scale
    }
    # really just enforce max width
    if br.x + br.width > lcBoundingRect.x + lcBoundingRect.width
      dx = br.x - lcBoundingRect.x
      @forcedWidth = lcBoundingRect.width - dx - 10
      @renderer = null

  getBoundingRect: (ctx, isEditing=false) ->
    # if isEditing == true, add X padding to account for carat
    unless @renderer
      if ctx
        @_makeRenderer(ctx)
      else
        throw "Must pass ctx if text hasn't been rendered yet"
    {
      @x, @y, width: @renderer.getWidth(true), height: @renderer.getHeight()
    }
  toJSON: -> {@x, @y, @text, @color, @font, @forcedWidth, @forcedHeight, @v}
  fromJSON: (data) -> createShape('Text', data)

  toSVG: ->
    # fallback: don't worry about auto-wrapping
    widthString = if @forcedWidth then "width='#{@forcedWidth}px'" else ""
    heightString = if @forcedHeight then "height='#{@forcedHeight}px'" else ""
    textSplitOnLines = @text.split(/\r\n|\r|\n/g)

    if @renderer
      textSplitOnLines = @renderer.lines

    "
    <text x='#{@x}' y='#{@y}'
          #{widthString} #{heightString}
          fill='#{@color}'
          style='font: #{@font};'>
      #{textSplitOnLines.map((line, i) =>
        dy = if i == 0 then 0 else '1.2em'
        return "<tspan x='#{@x}' dy='#{dy}' alignment-baseline='text-before-edge'>#{line}</tspan>"
      ).join('')}
    </text>
    "


HANDLE_SIZE = 10
MARGIN = 4
defineShape 'SelectionBox',
  constructor: (args={}) ->
    @shape = args.shape
    @backgroundColor = args.backgroundColor or null
    @_br = @shape.getBoundingRect(args.ctx)

  draw: (ctx) ->
    if @backgroundColor
      ctx.fillStyle = @backgroundColor
      ctx.fillRect(
        @_br.x - MARGIN, @_br.y - MARGIN,
        @_br.width + MARGIN * 2, @_br.height + MARGIN * 2)
    ctx.lineWidth = 1
    ctx.strokeStyle = '#000'
    ctx.setLineDash([2, 4])
    ctx.strokeRect(
      @_br.x - MARGIN, @_br.y - MARGIN,
      @_br.width + MARGIN * 2, @_br.height + MARGIN * 2)
    #ctx.strokeRect(@_br.x, @_br.y, @_br.width, @_br.height)

    ctx.setLineDash([])
    @_drawHandle(ctx, @getTopLeftHandleRect())
    @_drawHandle(ctx, @getTopRightHandleRect())
    @_drawHandle(ctx, @getBottomLeftHandleRect())
    @_drawHandle(ctx, @getBottomRightHandleRect())

  _drawHandle: (ctx, {x, y}) ->
    ctx.fillStyle = '#fff'
    ctx.fillRect(x, y, HANDLE_SIZE, HANDLE_SIZE)
    ctx.strokeStyle = '#000'
    ctx.strokeRect(x, y, HANDLE_SIZE, HANDLE_SIZE)

  getTopLeftHandleRect: ->
    {
      x: @_br.x - HANDLE_SIZE - MARGIN, y: @_br.y - HANDLE_SIZE - MARGIN,
      width: HANDLE_SIZE, height: HANDLE_SIZE
    }

  getBottomLeftHandleRect: ->
    {
      x: @_br.x - HANDLE_SIZE - MARGIN, y: @_br.y + @_br.height + MARGIN,
      width: HANDLE_SIZE, height: HANDLE_SIZE
    }

  getTopRightHandleRect: ->
    {
      x: @_br.x + @_br.width + MARGIN, y: @_br.y - HANDLE_SIZE - MARGIN,
      width: HANDLE_SIZE, height: HANDLE_SIZE
    }

  getBottomRightHandleRect: ->
    {
      x: @_br.x + @_br.width + MARGIN, y: @_br.y + @_br.height + MARGIN,
      width: HANDLE_SIZE, height: HANDLE_SIZE
    }

  getBoundingRect: ->
    {
      x: @_br.x - MARGIN, y: @_br.y - MARGIN,
      width: @_br.width + MARGIN * 2, height: @_br.height + MARGIN * 2
    }

  toSVG: -> ""


module.exports = {defineShape, createShape, JSONToShape, shapeToJSON}
