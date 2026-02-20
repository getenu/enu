import unittest2
import std/[tables, sets, sequtils]

import models/serializers {.all.}

import compiler/ast
import compiler/parser
import compiler/llstream
import compiler/idents

suite "Dependency Graph Topology":
  test "linear dependency":
    # A -> B -> C
    # Expected load order: C, B, A
    # (B depends on C, A depends on B)
    # Graph maps dependent -> dependencies
    var graph = initTable[string, seq[string]]()
    graph["A.nim"] = @["B.nim"]
    graph["B.nim"] = @["C.nim"]
    let nodes = @["A.nim", "B.nim", "C.nim"]

    let sorted = topo_sort(nodes, graph)

    # Check that dependencies appear BEFORE dependents in the list?
    # topo_sort logic: visit(node) -> visit dependencies -> add node.
    # So if A depends on B, visit(A) -> visit(B) -> add(B) -> add(A).
    # So dependencies come BEFORE dependents. Correct.

    check sorted.find("C.nim") < sorted.find("B.nim")
    check sorted.find("B.nim") < sorted.find("A.nim")
    check sorted.len == 3

  test "diamond dependency":
    # A -> B, A -> C, B -> D, C -> D
    # Expected: D before B and C, B/C before A
    var graph = initTable[string, seq[string]]()
    graph["A.nim"] = @["B.nim", "C.nim"]
    graph["B.nim"] = @["D.nim"]
    graph["C.nim"] = @["D.nim"]
    let nodes = @["A.nim", "B.nim", "C.nim", "D.nim"]

    let sorted = topo_sort(nodes, graph)

    check sorted.find("D.nim") < sorted.find("B.nim")
    check sorted.find("D.nim") < sorted.find("C.nim")
    check sorted.find("B.nim") < sorted.find("A.nim")
    check sorted.find("C.nim") < sorted.find("A.nim")
    check sorted.len == 4

  test "disconnected graph":
    # A -> B, C -> D
    var graph = initTable[string, seq[string]]()
    graph["A.nim"] = @["B.nim"]
    graph["C.nim"] = @["D.nim"]
    let nodes = @["A.nim", "B.nim", "C.nim", "D.nim"]

    let sorted = topo_sort(nodes, graph)

    check sorted.find("B.nim") < sorted.find("A.nim")
    check sorted.find("D.nim") < sorted.find("C.nim")
    check sorted.len == 4
