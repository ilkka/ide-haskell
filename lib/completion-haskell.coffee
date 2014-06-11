{Provider, Suggestion} = require 'autocomplete-plus'
fuzzaldrin = require 'fuzzaldrin'

{CompletionDatabase} = require './completion-db'
{isHaskellSource} = require './utils'
ArrayHelperModule = require './utils'

ArrayHelperModule.extendArray(Array)


class HaskellProvider extends Provider

  wordRegex: /([A-Z]\w*\.)*\w*/g

  initialize: (@editorView, @manager) ->
    @completionDatabase = new CompletionDatabase(@manager)

    # if saved, rebuild completion list
    @currentBuffer = @editor.getBuffer()
    @currentBuffer.on 'saved', @onSaved

    # if main database updated, rebuild completion list
    @manager.completionDatabase.on 'rebuild', @buildCompletionList
    @manager.completionDatabase.on 'updated', @setUpdatedFlag
    @completionDatabase.on 'updated', @setUpdatedFlag

    @buildCompletionList()

  dispose: ->
    @currentBuffer?.off 'saved', @onSaved
    @manager?.completionDatabase.off 'rebuild', @buildCompletionList
    @manager?.completionDatabase.off 'updated', @setUpdatedFlag
    @completionDatabase?.off 'updated', @setUpdatedFlag

  setUpdatedFlag: =>
    @databaseUpdated = true

  onSaved: =>
    return unless isHaskellSource @currentBuffer.getUri()

    # TODO remove current module from all providers modules

    @buildCompletionList()

  buildSuggestions: ->
    # try to rebuild completion list if database changed
    @rebuildWordList()
    return unless @totalWordList?

    selection = @editor.getSelection()
    prefix = @prefixOfSelection selection
    return unless prefix.length

    suggestions = @findSuggestionsForPrefix prefix
    return unless suggestions.length
    return suggestions

  findSuggestionsForPrefix: (prefix) ->
    # Filter the words using fuzzaldrin
    words = fuzzaldrin.filter @totalWordList, prefix

    # Builds suggestions for the words
    suggestions = for word in words when word isnt prefix
      new Suggestion this, word: word, prefix: prefix

    return suggestions

  # If database or prefixes was updated, rebuild world list
  rebuildWordList: ->
    return unless @databaseUpdated? and @databaseUpdated
    @databaseUpdated = false

    @totalWordList = []
    for module, prefixes of @prefixes
      if @completionDatabase.modules[module]?
        for word in @completionDatabase.modules[module]
          for prefix in prefixes
            @totalWordList.push "#{prefix}#{word.expr}"
      else if @manager.completionDatabase.modules[module]?
        for word in @manager.completionDatabase.modules[module]
          for prefix in prefixes
            @totalWordList.push "#{prefix}#{word.expr}"

  buildCompletionList: =>
    # check if main database is ready, and if its not, subscribe on ready event
    return unless isHaskellSource @currentBuffer.getUri()
    return unless @manager.completionDatabase.ready

    {imports, prefixes} = @parseImports()

    # remember prefixes and set update flag if it was changed
    if JSON.stringify(@prefixes) isnt JSON.stringify(prefixes)
      @prefixes = prefixes
      @setUpdatedFlag()

    # remove obsolete modules from local completion database
    @completionDatabase.removeObsolete imports

    # get completions for all modules in list
    fileName = @editor.getUri()
    for module in imports
      if not @manager.completionDatabase.update fileName, module
        @completionDatabase.update fileName, module

  # parse import modules from document buffer
  parseImports: ->
    imports = []
    prefixes = {}
    @editor.getBuffer().scan /^import\s+(qualified\s+)?([A-Z][^ \r\n]*)(\s+as\s+([A-Z][^ \r\n]*))?/g, ({match}) ->
      [_, isQualified, name, _, newQualifier] = match
      isQualified = isQualified?

      imports.push name

      # calculate prefixes for modules
      prefixes[name] = [] unless prefixes[name]?
      newQualifier = name unless newQualifier?
      prefixList = ["#{newQualifier}."]
      prefixList.push '' unless isQualified

      prefixList = prefixList.concat prefixes[name]
      prefixes[name] = prefixList.unique()

    # add prelude import by default
    imports.push 'Prelude'

    prefixList = ['Prelude.', '']
    prefixes['Prelude'] = [] if not prefixes['Prelude']?
    prefixList = prefixList.concat prefixes['Prelude']
    prefixes['Prelude'] = prefixList.unique()


    imports = imports.unique()
    return {imports, prefixes}


module.exports = {
  HaskellProvider
}