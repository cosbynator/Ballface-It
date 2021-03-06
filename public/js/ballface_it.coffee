VERSION = 0.1
SAVES_INDEX = 4
#
# Convinience 
#
Array.prototype.dict = ->
  ret = {}
  ret[e[0]] = e[1] for e in this
  ret

Array.prototype.groupBy = (f) ->
  ret = {}
  (ret[f(e)] or= []).push e for e in this
  ret

Array.prototype.last = -> if this.length == 0 then null else this[this.length - 1]
Array.prototype.first = -> if this.length == 0 then null else this[0]
Array.prototype.inGroupsOf = (num, fillNulls = false) ->
  ret = []
  (ret[Math.floor i / num] or= []).push this[i] for i in [0..this.length - 1]
  ret.last().push(null) for i in [ret.last().length..num - 1] if fillNulls && ret.last().length != num
  ret

aa = (name) -> (e) -> e[name] #Attr accessor

#Not placing on the object prototype due to serialization concerns
class Base
  constructor: ((@name, @get, @set) -> )
  getClass: ->
    @constructor

  setProperty: (name, klass, opts...) =>
    new klass(name, (=> this[name]), (val) =>
      this[name] = val
    , opts...)

  setAndNotifyProperty: (name, klass, opts...) =>
    new klass(name, (=> this[name]), (val) =>
      this[name] = val
      @levelModel.modelChanged()
    , opts...)

#
# Properties
#
class IntegerProperty extends Base
  newPropertyListNode: ->
    $("""
    <label for="#{@name}" class="name">#{@name}</label> 
    <input type='text' name="#{@name}" class="value" value="#{@get()}" />
    """).bind 'change', (e) =>
      @set parseInt(e.target.value, 10)
      $(e.target).val @get()

class FloatProperty extends Base
  newPropertyListNode: ->
    $("""
    <label for="#{@name}" class="name">#{@name}</label> 
    <input type='text' name="#{@name}" class="value" value="#{@get()}" />
    """).bind 'change', (e) =>
      @set parseFloat(e.target.value)
      $(e.target).val @get()

class StringProperty extends Base
  newPropertyListNode: ->
    $("""
    <label for="#{@name}" class="name">#{@name}</label> 
    <input type='text' name="#{@name}" class="value" value="#{@get()}" />
    """).bind 'change', (e) =>
      @set e.target.value
      $(e.target).val @get()

class BooleanProperty extends Base
  newPropertyListNode: ->
    $("""
      <label for="#{@name}" class="name">#{@name}</label> 
      <input type='checkbox' name="#{@name}" class="value" value="#{@name}" #{if @get() then 'checked' else ''} />
    """).bind 'change', (e) =>
      @set e.target.checked
      e.target.checked = @get()

class EnumProperty extends Base
  constructor: ((@name, @get, @set, @options) -> )
  newPropertyListNode: ->
    selectStrings = ("<option value='#{e}'#{if @get() == e then 'selected' else ''}>#{e}</option>" for e in @options).join("\n")
    $("""
      <label for="#{@name}" class="name">#{@name}</label> 
      <select name="#{name}">#{selectStrings}</select>
    """).bind 'change', (e) =>
      @set $(e.target).val()
      $(e.target).val @get()
#
# Widgets
# 
class LevelProperties extends Base
  constructor: (@node, @levelModel) ->
    @$node = $(@node)
    @levelModel.addModelChangeCallback(@redraw)
    @redraw()

  redraw: =>
    @$node.empty()
    for property in @levelModel.gameProperties()
      @$node.append(property.newPropertyListNode()).append("<br />")

class LevelCanvas extends Base
  constructor: (@canvas, @levelModel) ->
    @draggingObject = null
    @$canvas = $(@canvas)
    $(@canvas).mouseup @mouseUp
    $(@canvas).mousedown @mouseDown
    $(@canvas).mousemove @mouseMove
    @levelModel.addModelChangeCallback(@redraw)
    $(@canvas).droppable {
      drop: (event,ui) =>
        dPos = $(@canvas).offset()
        relativeTop = ui.offset.top - dPos.top
        relativeLeft = ui.offset.left - dPos.left
        klass = @levelModel.gameObjectClassByName[ui.draggable.data("gameObjectClass")]
        gameObject = new klass(@levelModel)
        gameObject.x = relativeLeft + gameObject.width * gameObject.weightedOriginX
        gameObject.y = relativeTop + gameObject.height* gameObject.weightedOriginY
        @levelModel.addGameObject gameObject
    }

  mouseDown: (e) =>
    e.preventDefault()
    hit = @levelModel.hitTest(e.offsetX, e.offsetY)
    @didDrag = false
    if hit != null
      @draggingObject = hit
      @dragLastX = e.offsetX
      @dragLastY = e.offsetY
      @$canvas.css('cursor', 'move')
    @startX = e.offsetX
    @startY = e.offsetY
    if @levelModel.selectedObject
      @startedRotation = true
      @startRotation = @levelModel.selectedObject.rotation

  mouseMove: (e) =>
    e.preventDefault()
    if @startedRotation && e.altKey && @levelModel.selectedObject != null
      @$canvas.css('cursor', 'e-resize')
      @levelModel.selectedObject.rotation = @startRotation + (e.offsetX - @startX)
      @redraw()
      return

    if @draggingObject == null
      return

    @didDrag = true
    @draggingObject.x += e.offsetX - @dragLastX
    @draggingObject.y += e.offsetY - @dragLastY
    @dragLastX = e.offsetX
    @dragLastY = e.offsetY
    @redraw()

  mouseUp: (e) =>
    e.preventDefault()
    if !@didDrag
      hit = @levelModel.hitTest(e.offsetX, e.offsetY)
      if hit != null
        @levelModel.select hit
      else
        @levelModel.unselectAll()
    else
      @levelModel.reorder()

    @draggingObject = null
    @startedRotation = false
    @$canvas.css('cursor', '')

  clear: ->
    @canvas.width = @levelModel.width

  redraw: =>
    @clear()
    context = @canvas.getContext "2d"
    for gameObject in @levelModel.gameObjects
      gameObject.draw context

class LevelListing extends Base
  constructor: (@node, @levelModel) ->
    @$node = $(@node)
    @$node.html "<li>No objects...</li>"
    @levelModel.addModelChangeCallback(@redraw)
    $(".listingObject").live 'click', ->
      levelModel.select(levelModel.getObjectById($(this).data('id')))

  clear: =>
    @$node.empty()

  redraw: =>
    @clear()
    for gameObject in @levelModel.gameObjects
      @$node.append($("<li class='listingObject#{if gameObject.selected then' selected' else ''}' data-id='#{gameObject.id}'>#{gameObject.getClass().name} @ #{gameObject.x}</li>"))

class ObjectInspector extends Base
  constructor: (@node, @levelModel) ->
    @$node = $(@node)
    @redraw()
    @levelModel.addModelChangeCallback(@redraw)
    $(".gameObjectProperty .value").live 'change', (e) =>
      gameObject = @levelModel.getObjectById($(e.target).data('id'))
      gameProperty = gameObject.getClass().getGamePropertyByName(e.target.name)
      gameObject[e.target.name] = gameProperty.convertString(e.target.value)
      $(e.target).val gameObject[e.target.name]
      @levelModel.modelChanged()

  redraw: =>
    selected = @levelModel.selectedObject
    if selected == null
      @$node.text "No selection..."
    else
      @$node.empty().append("<h3>#{selected.getClass().name} Properties</h3>")
      for property in selected.gameProperties()
        @$node.append(property.newPropertyListNode()).append("<br />")

class GameObjectSelector extends Base
  constructor: (@node, @levelModel) ->
    groups = @levelModel.gameObjectClasses.groupBy aa("groupName")
    for groupName, gameObjectClasses of groups
      html = "<div class='gameObjectGroup'><div class='gameObjectGroupToggle hidden'>#{groupName}</div><table style='display:none;'>"
      for gameObjectGroup in gameObjectClasses.inGroupsOf(4, true)
        html += "<tr>"
        html += (for gameObjectClass in gameObjectGroup
          if gameObjectClass == null
            "<td></td>"
          else
            """
              <td class="gameObject">
                <img src="#{gameObjectClass.imageObject.src}" class="gameObjectImage" data-game-object-class="#{gameObjectClass.name}"/>
                <br />
                <span class="gameObjectName">#{gameObjectClass.name}</span>
              </td>
            """
        ).join("")
        html += "</tr>"
      html += "</table></div>"
      $html = $(html)
      $html.find(".gameObjectGroupToggle").click (e) ->
        $(this).next("table").toggle('slow')
        $(this).toggleClass("hidden")

      $(@node).append $html

    $(".gameObjectImage" ).draggable {helper: 'clone'}

class SavedLister extends Base
  constructor: (@node, @levelModel) ->
    @$node = $(@node)
    @data = []
    @redraw()

  repopulate: ->
    @$node.html "<div class='loader'/>"
    $.get "/list", (data) =>
      @data = data
      @redraw()

  redraw: ->
    html = for levelData in @data
      saveTime = new Date(levelData.saveTime)
      nameData = "#{levelData.name} @ #{saveTime}"
      """
      <li class="levelItem">
        <span class="name">#{levelData.name}</span> @ #{saveTime}
        [<a href="/download/#{levelData.id}" class="loadLevel" data-name="#{nameData}">Load</a>]
        [<a href="/download/#{levelData.id}">Download</a>]
        [<a href="/delete/#{levelData.id}" class="deleteLevel" data-name="#{nameData}">Delete</a>]
      </li>
      """

    @$node.html "<ul>#{html.join("")}</ul>"
    @$node.find(".loadLevel").click (e) =>
      e.preventDefault()
      if confirm("Are you sure you want to load #{$(e.target).data('name')}? This will trash your current level.")
        $.get e.target.href, (data) =>
          if data.level
            @levelModel.deserialize data.level
            @levelModel.id = data.id

    @$node.find(".deleteLevel").click (e) =>
      e.preventDefault()
      if confirm("Are you sure you want to delete #{$(e.target).data('name')}?")
        $.get e.target.href, =>
          @repopulate()

#
# Game objects
# 
class GameObject extends Base
  @name: this.name
  @groupName: "Game Objects"
  @counter = 0

  @deserializeNew: (data, levelModel) =>
    ret = new this(levelModel)
    for property in ret.gameProperties()
      property.set(data[property.name]) if data[property.name]?
    ret.y = levelModel.height - data.y
    ret

  @gameObjectImage: (name) ->
    ret = new Image()
    ret.src = "data/game_objects/#{name}"
    ret

  constructor: (@levelModel) ->
    @x = 0
    @y = 0
    @imageObject = @getClass().imageObject
    @width = @imageObject.width
    @height = @imageObject.height
    GameObject.counter += 1
    @id = GameObject.counter
    @selected = false
    @weightedOriginX = 0.5
    @weightedOriginY = 0.5
    @rotation = 0
    @restitution = 0.5
    @density = 100.0
    @friction = 0.1

  nodeSpaceContext: (context) ->
    context.translate(@x, @y)
    context.rotate(@rotation * Math.PI / 180)
    context.translate(-@x, -@y)

  draw: (context) ->
    context.save()
    @nodeSpaceContext(context)
    x = @x - @weightedOriginX * @width
    y = @y - @weightedOriginY * @height
    extra = 2
    if @selected
      context.fillStyle = "#00f"
      context.fillRect x - extra,y - extra,@width + 2*extra,@height + 2*extra
    context.drawImage @getClass().imageObject, x, y, @width, @height
    context.restore()

  convertToLocalSpace: (x,y) ->
    xp = x - @x
    yp = y - @y
    st = Math.sin(@rotation * Math.PI / 180)
    ct = Math.cos(@rotation * Math.PI / 180)
    xr = ct * xp + st * yp
    yr = -st * xp + ct * yp
    [xr, yr]
  
  gameProperties: ->
    @_gameProperties or= (@setAndNotifyProperty(e...) for e in [
        ["x", IntegerProperty],
        ["y", IntegerProperty],
        ["rotation", FloatProperty],
        ["density", FloatProperty],
        ["friction", FloatProperty],
        ["restitution", FloatProperty]
      ])

  hitTest: (x,y) ->
    [localX, localY] =  @convertToLocalSpace(x,y)
    newX = localX + @x
    newY = localY + @y
    drawX = @x - @weightedOriginX * @width
    drawY = @y - @weightedOriginY * @height
    newX >= drawX && newX <= drawX + @width && newY >= drawY && newY <= drawY + @height

  serialized: ->
    ret = {
      type: @getClass().name
    }
    for property in @gameProperties()
      ret[property.name] = property.get()
    #hack to flip y to match opengl
    ret.y = @levelModel.height - ret.y
    ret

class GameEntity extends GameObject
  @groupName = "Entities"

class SpawnPoint extends GameEntity
  @imageObject: @gameObjectImage("ballface.png")
  @name = "Ballface Spawn"

  constructor: (@levelModel) ->
    super(@levelModel)
    @normalizationForce = 200.0
    @maxVelocity = 100.0

  gameProperties: ->
    @_gameProperties or= super().concat(@setAndNotifyProperty(e...) for e in [
      ["normalizationForce", FloatProperty],
      ["maxVelocity", FloatProperty]
    ])

class Paddle extends GameObject
  @name: "Wooden Paddle"
  @imageObject: @gameObjectImage("paddle.png")
  constructor: (@levelModel) ->
    super(@levelModel)
    @weightedOriginX = 0.5
    @weightedOriginY = 1.0

class GravityBall extends GameObject
  @name: "Gravity Ball"
  @imageObject: @gameObjectImage("gravityball.png")

class Fish extends GameObject
  @name: "Fish"
  @imageObject: @gameObjectImage("fishEnemy.png")

class Toothbrush extends GameObject
  @name = "Toothbrush"
  @imageObject: @gameObjectImage("toothbrush.png")

class Spring extends GameObject
  @groupName = "Contraptions"
  @imageObject: @gameObjectImage("springIcon.png")
  @springBodyImage = new Image()
  @springCapImage = new Image()
  @springBodyImage.src = "data/game_objects/springBody.png"
  @springCapImage.src = "data/game_objects/springCap.png"

  constructor: (@levelModel) ->
    super(@levelModel)
    @springConstant = 5.0
    @dampingConstant = 0.1
    @maxExtension = 80.0
    @startExtension = 40.0
    @unextendedLength = 60.0
    @springsOnCollision = true
    @stopsCollider = false
    @weightedOriginX = 0.5
    @weightedOriginY = 1.0
    @height = @startExtension

  draw: (context) ->
    @height = @startExtension
    context.save()
    @nodeSpaceContext(context)
    x = @x - @weightedOriginX * @width
    y = @y - @weightedOriginY * @height
    extra = 2
    if @selected
      context.fillStyle = "#00f"
      context.fillRect x - extra,y - extra,@width + 2*extra,@height + 2*extra
      context.strokeStyle = "#000"
      context.lineWidth = 2
      context.save()
      context.moveTo(x + @width / 2,y)
      context.lineTo(x + @width / 2,y - 480)
      context.stroke()
      context.restore()

    context.fillStyle = "rgba(0,255,0,0.2)"
    context.fillRect x, y + @height - @unextendedLength, @width,  @unextendedLength - @height
    context.fillStyle = "rgba(255,0,0,0.2)"
    context.fillRect x, y + @height - @maxExtension, @width,  @maxExtension - @unextendedLength
    context.drawImage @getClass().springBodyImage, x, y, @width, @height
    context.drawImage @getClass().springCapImage, x, y, @width, @getClass().springCapImage.height
    context.restore()

  gameProperties: ->
    @_gameProperties or= super().concat(@setAndNotifyProperty(e...) for e in [
      ["startExtension", FloatProperty],
      ["maxExtension", FloatProperty],
      ["unextendedLength", FloatProperty],
      ["springConstant", FloatProperty],
      ["dampingConstant", FloatProperty],
      ["springOnCollision", BooleanProperty],
      ["stopsCollider", BooleanProperty]
    ])

class Debris extends GameObject
  @groupName = "Debris"
  constructor: (@levelModel) ->
    super(@levelModel)
    @staticBody = true
    @damageCaused = 0

  gameProperties: ->
    @_gameProperties or= super().concat(@setAndNotifyProperty(e...) for e in [
      ["staticBody", BooleanProperty],
      ["damageCaused", IntegerProperty]
    ])

class Lunch extends GameObject
  @name = "Lunch Bag"
  @imageObject: @gameObjectImage("lunch.png")
  constructor: (@levelModel) ->
    super(@levelModel)
    @foodVelocityRatio = 1.0

  gameProperties: ->
    @_gameProperties or= super().concat(@setAndNotifyProperty(e...) for e in [
      ["foodVelocityRatio", FloatProperty],
    ])

class LargePlank extends Debris
  @name: "LargePlank"
  @imageObject: @gameObjectImage("Planks-4x1.png")

class MediumPlank extends Debris
  @name: "MediumPlank"
  @imageObject: @gameObjectImage("Planks-3x1.png")

class SmallPlank extends Debris
  @name: "SmallPlank"
  @imageObject: @gameObjectImage("Planks-2x1.png")

class StopSign extends Debris
  @name = "Stop"
  @imageObject: @gameObjectImage("stop.png")

class OneWaySign extends Debris
  @name = "One Way"
  @imageObject: @gameObjectImage("oneway.png")

class YieldSign extends Debris
  @name = "Yield"
  @imageObject: @gameObjectImage("yield.png")

class GuardRail extends Debris
  @name = "GuardRail"
  @imageObject: @gameObjectImage("GuardRail.png")

class Girders1 extends Debris
  @name = "Girders1"
  @imageObject: @gameObjectImage("Girders1.png")

class Girders2 extends Debris
  @name = "Girders2"
  @imageObject: @gameObjectImage("Girders2.png")

class Girders3 extends Debris
  @name = "Girders3"
  @imageObject: @gameObjectImage("Girders3.png")

class Beanz extends Debris
  @name = "Beanz"
  @imageObject: @gameObjectImage("Beanz.png")

class Recycler extends Debris
  @name = "Recycler"
  @imageObject: @gameObjectImage("Recycler.png")

class OldDoor extends Debris
  @name = "OldDoor"
  @imageObject: @gameObjectImage("OldDoor.png")

class CosbyLetter extends GameObject
  @groupName = "Letters"

class CosbyLetterC extends CosbyLetter
  @imageObject: @gameObjectImage("letterC.png")

class CosbyLetterO extends CosbyLetter
  @imageObject: @gameObjectImage("letterO.png")

class CosbyLetterS extends CosbyLetter
  @imageObject: @gameObjectImage("letterS.png")

class CosbyLetterB extends CosbyLetter
  @imageObject: @gameObjectImage("letterB.png")

class CosbyLetterY extends CosbyLetter
  @imageObject: @gameObjectImage("letterY.png")

#
# -The- level
#
class LevelModel extends Base
  constructor: ->
    @gameObjects = []
    @gameObjectsById = {}
    @selectedObject = null
    @modelChangeCallbacks = []
    @width = 960
    @height = 320
    @paddleAngularDamping = 2
    @paddleDensity = 300.0
    @paddleFriction = 5.0
    @paddleRestitution = 0.5
    @levelName = "Unnamed level"
    @controlType = "Paddle"
    @gameObjectClasses = [SpawnPoint,
        Paddle, Fish, Toothbrush, Lunch,  GravityBall,
        SmallPlank, MediumPlank, LargePlank, Spring, StopSign, OneWaySign, YieldSign, GuardRail
        Girders1, Girders2, Girders3, Beanz, Recycler, OldDoor,
        CosbyLetterC, CosbyLetterO, CosbyLetterS, CosbyLetterB, CosbyLetterY
    ]
    @gameObjectClassByName = ([c.name,c] for c in @gameObjectClasses).dict()
    @levelModel = this #For property helper methods

  hitTest: (x,y) ->
    for gameObject in @gameObjects
      if gameObject.hitTest x,y
        return gameObject
    null

  select: (objectName) ->
    if @selectedObject != objectName
      if @selectedObject != null
        @selectedObject.selected = false
      @selectedObject = objectName
      @selectedObject.selected = true
      @modelChanged()

  unselectAll: ->
    if @selectedObject != null
      @selectedObject.selected = false
      @selectedObject = null
      @modelChanged()

  getObjectById: (id) ->
    @gameObjectsById[parseInt id, 10]

  addModelChangeCallback: (callback) ->
    @modelChangeCallbacks.push callback

  modelChanged: ->
    e(this) for e in @modelChangeCallbacks

  reorder: ->
    @gameObjects.sort (a,b) -> a.x - b.x
    @modelChanged()

  addGameObject: (gameObject) ->
    @gameObjects.push(gameObject)
    @gameObjectsById[gameObject.id] = gameObject
    @reorder()

  deleteGameObject: (gameObject) ->
    @gameObjects = (e for e in @gameObjects when e.id != gameObject.id)
    delete @gameObjectsById[gameObject.id]
    if @selectedObject == gameObject
      @unselectAll()
    @modelChanged()

  gameProperties: ->
    @_gameProperties or= [
      @setProperty("levelName", StringProperty),
      @setAndNotifyProperty("width", IntegerProperty),
      @setProperty("paddleAngularDamping", FloatProperty),
      @setProperty("paddleDensity", FloatProperty),
      @setProperty("paddleRestitution", FloatProperty),
      @setProperty("paddleFriction", FloatProperty),
      @setProperty("controlType", EnumProperty, ["Paddle", "Explosion", "Yoyo"])
    ]

  serialized: ->
    ret = {
      objects: e.serialized() for e in @gameObjects
      editorVersion: VERSION
    }
    for property in @gameProperties()
      ret[property.name] = property.get()
    ret

  deserialize: (object) ->
    @selectedObject = null
    @gameObjects = []
    @gameObjectsById = {}
    for property in @gameProperties()
      property.set(object[property.name]) if object[property.name]?
    for e in object.objects
      gameObject = @gameObjectClassByName[e.type].deserializeNew(e, this)
      @addGameObject(gameObject)
      @modelChanged()

$(document).ready ->
  levelModel = new LevelModel
  levelCanvas = new LevelCanvas $("#editorCanvas").get(0), levelModel
  levelListing = new LevelListing $("#levelListing").get(0), levelModel
  objectInspector = new ObjectInspector $("#objectInspector").get(0), levelModel
  levelProperties = new LevelProperties $("#levelProperties").get(0), levelModel
  gameObjectSelector = new GameObjectSelector $("#gameObjects").get(0), levelModel
  savedLister = new SavedLister $("#levelSaves").get(0), levelModel

  $("#loadingDiv").dialog
    modal: true
    dialogClass: 'loadingDivDialog'
    draggable: false
    resizable: false
    autoOpen: false
    show: 'fade'
    hide: 'explode'

  startLoading = ->
    $("loadingDivSpinner").show()
    $("#loadingDiv").dialog 'open'
  stopLoading = ->
    setTimeout(->
      $("#loadingDiv").dialog 'close'
    , 200)

  $("#objectTabs").tabs().bind 'tabsselect', (e, ui) ->
    if ui.index == SAVES_INDEX
      savedLister.repopulate()

  $("#saveLevel").submit (e) ->
    e.preventDefault()
    $("#saveLevelSubmit").attr 'disabled', true
    data = {level: levelModel.serialized()}
    data.id = levelModel.id if levelModel.id?
    startLoading()
    $.ajax {
      type: "POST"
      url: "/save"
      data: JSON.stringify(data)
      dataType: "json"
      contentType: "application/json"
      success: (data) ->
        levelModel.id = data.id
        savedLister.repopulate()
        stopLoading()
      error: ->
        stopLoading()
        $("#saveLevelSubmit").attr 'disabled', false
        alert 'Failed to save!'
    }

  levelModel.addModelChangeCallback ->
    $("#saveLevelSubmit").attr 'disabled', false

  $(document).bind 'keydown', (e) ->
    if levelModel.selectedObject != null && e.keyCode == 46 && confirm("Are you sure you want to delete the #{levelModel.selectedObject.getClass().name}?") #Delete
      e.preventDefault()
      levelModel.deleteGameObject levelModel.selectedObject
    else if e.ctrlKey && (e.keyCode == 83 || e.keyCode == 115) || e.keyCode == 19 #Control S
      e.preventDefault()
      $("#saveLevel").submit() unless $("#saveLevelSubmit").attr('disabled')
