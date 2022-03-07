# ModuleDependencyVisualizer

## Executing

`mix run run.exs "/Users/elitau/Documents/workspace/freigabe/lib/**/*.{ex, exs}"`

## Integration with vs code

Limit graph to nodes connected to current file, Maybe with a [watcher task](https://code.visualstudio.com/docs/editor/tasks#_background-watching-tasks).

### Wishlist

- [ ] Trigger re-rendering of graph with a task.
- [ ] Trigger re-rendering of graph upon file save.
- [ ] Render graph in a window alongside or in a tab of vs code.
- [ ] Click on a node in the graph navigates to the corresponding file in a vs code tab [1].
- [ ] Navigating to a file in vs code highlights the corresponding node in the graph.
- [ ] Show only 7+/-2 nodes visible at once - rest is omitted for easier comprehension.
- [partly] Show only relevant nodes like domain models, services, events, consumers, publishers etc.
- [ ] Navigate the graph with keyboard.

[1] [VS Code interactive graphviz extension](https://github.com/tintinweb/vscode-interactive-graphviz)

## Complete App Graph

Show the whole application in one picture.

## Allow to filter

The `include` filter keeps only the __origin__ nodes that contains one the given
names. Afterwards the `exclude` filter removes all outgoing dependencies that
contains one the given names.
