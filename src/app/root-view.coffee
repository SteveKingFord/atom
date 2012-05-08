$ = require 'jquery'
{$$} = require 'space-pen'
fs = require 'fs'
_ = require 'underscore'

{View} = require 'space-pen'
Buffer = require 'buffer'
Editor = require 'editor'
FileFinder = require 'file-finder'
Project = require 'project'
VimMode = require 'vim-mode'
CommandPanel = require 'command-panel'
Pane = require 'pane'
PaneColumn = require 'pane-column'
PaneRow = require 'pane-row'
StatusBar = require 'status-bar'

module.exports =
class RootView extends View
  @content: ->
    @div id: 'root-view', tabindex: -1, =>
      @div id: 'horizontal', outlet: 'horizontal', =>
        @div id: 'panes', outlet: 'panes'

  @deserialize: ({ projectPath, panesViewState, extensionStates }) ->
    rootView = new RootView(pathToOpen: projectPath)
    rootView.setRootPane(rootView.deserializeView(panesViewState)) if panesViewState
    rootView.extensionStates = extensionStates if extensionStates
    rootView

  extensions: null
  extensionStates: null

  initialize: ({ pathToOpen }) ->
    @handleEvents()

    @extensions = {}
    @extensionStates = {}
    @commandPanel = new CommandPanel({rootView: this})

    @setTitle()
    @project = new Project(pathToOpen)
    if pathToOpen? and fs.isFile(pathToOpen)
      @open(pathToOpen)

  serialize: ->
    projectPath: @project?.path
    panesViewState: @panes.children().view()?.serialize()
    extensionStates: @serializeExtensions()

  handleEvents: ->
    @on 'toggle-file-finder', => @toggleFileFinder()
    @on 'show-console', => window.showConsole()
    @on 'focus', (e) =>
      if @activeEditor()
        @activeEditor().focus()
        false
      else
        @setTitle(@project?.getPath())

    @on 'active-editor-path-change', (e, path) =>
      @project.setPath(path) unless @project.getPath()
      @setTitle(path)

  afterAttach: (onDom) ->
    @focus() if onDom

  serializeExtensions:  ->
    extensionStates = {}
    for name, extension of @extensions
      extensionStates[name] = extension.serialize()

    extensionStates

  deserializeView: (viewState) ->
    switch viewState.viewClass
      when 'Pane' then Pane.deserialize(viewState, this)
      when 'PaneRow' then PaneRow.deserialize(viewState, this)
      when 'PaneColumn' then PaneColumn.deserialize(viewState, this)
      when 'Editor' then Editor.deserialize(viewState, this)

  activateExtension: (extension) ->
    @extensions[extension.name] = extension
    extension.activate(this, @extensionStates[extension.name])

  deactivate: ->
    atom.rootViewStates[$windowNumber] = @serialize()
    extension.deactivate() for name, extension of @extensions
    @remove()

  open: (path, changeFocus=true) ->
    buffer = @project.open(path)

    if @activeEditor()
      @activeEditor().setBuffer(buffer)
    else
      editor = new Editor({ buffer })
      pane = new Pane(editor)
      @panes.append(pane)
      if changeFocus
        editor.focus()
      else
        @makeEditorActive(editor)

  editorFocused: (editor) ->
    @makeEditorActive(editor) if @panes.containsElement(editor)

  makeEditorActive: (editor) ->
    previousActiveEditor = @panes.find('.editor.active').view()
    previousActiveEditor?.removeClass('active').off('.root-view')
    editor
      .addClass('active')
      .on 'editor-path-change.root-view', =>
        @trigger 'active-editor-path-change', editor.buffer.path

    if not previousActiveEditor or editor.buffer.path != previousActiveEditor.buffer.path
      @trigger 'active-editor-path-change', editor.buffer.path

  setTitle: (title='untitled') ->
    document.title = title

  editors: ->
    @panes.find('.editor').map -> $(this).view()

  activeEditor: ->
    if (editor = @panes.find('.editor.active')).length
      editor.view()
    else
      @panes.find('.editor:first').view()

  setRootPane: (pane) ->
    @panes.empty()
    @panes.append(pane)
    @adjustPaneDimensions()

  adjustPaneDimensions: ->
    rootPane = @panes.children().first().view()
    rootPane?.css(width: '100%', height: '100%', top: 0, left: 0)
    rootPane?.adjustDimensions()

  toggleFileFinder: ->
    return unless @project.getPath()?

    if @fileFinder and @fileFinder.parent()[0]
      @fileFinder.remove()
      @fileFinder = null
    else
      @project.getFilePaths().done (paths) =>
        relativePaths = (@project.relativize(path) for path in paths)
        @fileFinder = new FileFinder
          paths: relativePaths
          selected: (relativePath) => @open(relativePath)
        @append @fileFinder
        @fileFinder.editor.focus()

  remove: ->
    editor.remove() for editor in @editors()
    super
