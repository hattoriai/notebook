// The example extension: a callout box (KotobaDev.Nodes.Callout, type
// "notebook-callout").
//
// It adds
//
//   * the CalloutNode, an element node of inline content;
//   * TOGGLE_CALLOUT_COMMAND, which turns the blocks at the selection into
//     callouts, or back into paragraphs;
//   * a toolbar button that runs the command, pressed in a callout (the
//     toolbar says "Callout on" or "Callout off");
//   * the `!!! ` Markdown shortcut.
//
// Kotoba calls the default export once for each editor, with the editor's
// copies of lexical, @lexical/utils and @lexical/selection: the classes
// extend the same Lexical as the built-in nodes. The register function returns its cleanup, which runs when the
// editor is destroyed.
//
// `window.notebookCallouts` counts the registrations that have not been
// cleaned up, for the browser tests.

export default ({ lexical, utils, selection }) => {
  class CalloutNode extends lexical.ElementNode {
    static getType() {
      return "notebook-callout"
    }

    static clone(node) {
      return new CalloutNode(node.__key)
    }

    static importJSON(json) {
      return new CalloutNode().updateFromJSON(json)
    }

    exportJSON() {
      return {...super.exportJSON(), type: "notebook-callout", version: 1}
    }

    createDOM() {
      const element = document.createElement("aside")
      element.className = "notebook-callout"
      return element
    }

    updateDOM() {
      return false
    }

    // Enter at the end of a callout makes a paragraph after it.
    insertNewAfter(_selection, restoreSelection) {
      const paragraph = lexical.$createParagraphNode()
      this.insertAfter(paragraph, restoreSelection)
      return paragraph
    }

    collapseAtStart() {
      const paragraph = lexical.$createParagraphNode()
      this.getChildren().forEach((child) => paragraph.append(child))
      this.replace(paragraph)
      return true
    }
  }

  const $isCallout = (node) => node instanceof CalloutNode

  const $inCallout = () => {
    const current = lexical.$getSelection()
    if (!lexical.$isRangeSelection(current)) return false
    return utils.$findMatchingParent(current.anchor.getNode(), $isCallout) !== null
  }

  const TOGGLE_CALLOUT_COMMAND = lexical.createCommand("TOGGLE_CALLOUT_COMMAND")

  return {
    name: "callout",
    nodes: [CalloutNode],

    markdown: [
      {
        dependencies: [CalloutNode],
        type: "element",
        regExp: /^!!!\s/,
        export: (node, exportChildren) => ($isCallout(node) ? `!!! ${exportChildren(node)}` : null),
        replace: (parent, children) => {
          const callout = new CalloutNode()
          callout.append(...children)
          parent.replace(callout)
          callout.select(0, 0)
        },
      },
    ],

    toolbar: [
      {
        command: "toggle",
        label: "Callout",
        icon: () => {
          const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
          svg.setAttribute("viewBox", "0 0 24 24")
          svg.setAttribute("width", "18")
          svg.setAttribute("height", "18")
          svg.setAttribute("fill", "none")
          svg.setAttribute("stroke", "currentColor")
          svg.setAttribute("stroke-width", "2")
          const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
          path.setAttribute("d", "M12 8v4m0 4h.01M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0")
          svg.append(path)
          return svg
        },
        run: (editor) => editor.dispatchCommand(TOGGLE_CALLOUT_COMMAND, undefined),
        isActive: $inCallout,
      },
    ],

    register(editor) {
      window.notebookCallouts = (window.notebookCallouts ?? 0) + 1

      const unregister = editor.registerCommand(
        TOGGLE_CALLOUT_COMMAND,
        () => {
          const current = lexical.$getSelection()
          if (!lexical.$isRangeSelection(current)) return false
          const inCallout = $inCallout()
          selection.$setBlocksType(current, () => (inCallout ? lexical.$createParagraphNode() : new CalloutNode()))
          return true
        },
        lexical.COMMAND_PRIORITY_EDITOR,
      )

      return () => {
        window.notebookCallouts -= 1
        unregister()
      }
    },
  }
}
