%%%-------------------------------------------------------------------
%%% @author Krzysztof Trzepla
%%% @copyright (C) 2017: Krzysztof Trzepla
%%% This software is released under the MIT license cited in 'LICENSE.md'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc
%%% This module provides B+ tree node management functions.
%%% @end
%%%-------------------------------------------------------------------
-module(bp_tree_node).
-author("Krzysztof Trzepla").

-include("bp_tree.hrl").

%% API exports
-export([new/2]).
-export([key/2, value/2, size/1]).
-export([right_sibling/1, set_right_sibling/2]).
-export([child/2, child_with_sibling/2, leftmost_child/1]).
-export([find/2, lower_bound/2]).
-export([insert/3, remove/2, merge/3, split/1]).
-export([rotate_right/3, rotate_left/3, replace_key/3]).

-type id() :: any().

-export_type([id/0]).

%%====================================================================
%% API functions
%%====================================================================

%%--------------------------------------------------------------------
%% @doc
%% Creates B+ tree node.
%% @end
%%--------------------------------------------------------------------
-spec new(bp_tree:order(), boolean()) -> bp_tree:tree_node().
new(Order, Leaf) ->
    #bp_tree_node{
        leaf = Leaf,
        children = bp_tree_array:new(2 * Order + 1)
    }.

%%--------------------------------------------------------------------
%% @doc
%% Returns key at a position or fails with a out of range error.
%% @end
%%--------------------------------------------------------------------
-spec key(pos_integer(), bp_tree:tree_node()) ->
    {ok, bp_tree:value()} | {error, out_of_range}.
key(Pos, #bp_tree_node{leaf = true, children = Children}) ->
    bp_tree_array:get({key, Pos}, Children).

%%--------------------------------------------------------------------
%% @doc
%% Returns value at a position or fails with a out of range error.
%% @end
%%--------------------------------------------------------------------
-spec value(pos_integer(), bp_tree:tree_node()) ->
    {ok, bp_tree:value()} | {error, out_of_range}.
value(Pos, #bp_tree_node{leaf = true, children = Children}) ->
    bp_tree_array:get({left, Pos}, Children).

%%--------------------------------------------------------------------
%% @doc
%% Returns number of node's children.
%% @end
%%--------------------------------------------------------------------
-spec size(bp_tree:tree_node()) -> non_neg_integer().
size(#bp_tree_node{children = Children}) ->
    bp_tree_array:size(Children).

%%--------------------------------------------------------------------
%% @doc
%% Returns child node on path from a root to a leaf associated with a key.
%% @end
%%--------------------------------------------------------------------
-spec child(bp_tree:key(), bp_tree:tree_node()) ->
    {ok, id()} | {error, not_found}.
child(_Key, #bp_tree_node{leaf = true}) ->
    {error, not_found};
child(Key, #bp_tree_node{leaf = false, children = Children}) ->
    Pos = bp_tree_array:lower_bound(Key, Children),
    case bp_tree_array:get({left, Pos}, Children) of
        {ok, NodeId} ->
            {ok, NodeId};
        {error, out_of_range} ->
            {ok, _NodeId} = bp_tree_array:get({right, last}, Children)
    end.

%%--------------------------------------------------------------------
%% @doc
%% Returns child node with sibling on path from a root to a leaf associated with
%% a key.
%% @end
%%--------------------------------------------------------------------
-spec child_with_sibling(bp_tree:key(), bp_tree:tree_node()) ->
    {ok, id(), bp_tree:key(), id()} | {error, not_found}.
child_with_sibling(_Key, #bp_tree_node{leaf = true}) ->
    {error, not_found};
child_with_sibling(Key, #bp_tree_node{leaf = false, children = Children}) ->
    Pos = bp_tree_array:lower_bound(Key, Children),
    case bp_tree_array:get({left, Pos}, Children) of
        {ok, NodeId} ->
            case bp_tree_array:get({left, Pos - 1}, Children) of
                {ok, LNodeId} ->
                    {ok, Key2} = bp_tree_array:get({key, Pos - 1}, Children),
                    {ok, LNodeId, Key2, NodeId};
                {error, out_of_range} ->
                    {ok, Key2} = bp_tree_array:get({key, Pos}, Children),
                    {ok, RNodeId} = bp_tree_array:get({right, Pos}, Children),
                    {ok, NodeId, Key2, RNodeId}
            end;
        {error, out_of_range} ->
            {ok, Key2} = bp_tree_array:get({key, last}, Children),
            {ok, {LNodeId, RNodeId}} = bp_tree_array:get({both, last}, Children),
            {ok, LNodeId, Key2, RNodeId}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Returns leftmost child node on path from a root to a leaf.
%% @end
%%--------------------------------------------------------------------
-spec leftmost_child(bp_tree:tree_node()) ->
    {ok, id()} | {error, not_found}.
leftmost_child(#bp_tree_node{leaf = true}) ->
    {error, not_found};
leftmost_child(#bp_tree_node{leaf = false, children = Children}) ->
    {ok, _NodeId} = bp_tree_array:get({left, first}, Children).

%%--------------------------------------------------------------------
%% @doc
%% Returns right sibling of a leaf node.
%% @end
%%--------------------------------------------------------------------
-spec right_sibling(bp_tree:tree_node()) ->
    {ok, id()} | {error, not_found}.
right_sibling(#bp_tree_node{leaf = true, children = Children}) ->
    case bp_tree_array:get({right, last}, Children) of
        {ok, ?NIL} -> {error, not_found};
        {ok, NodeId} -> {ok, NodeId};
        {error, out_of_range} -> {error, not_found}
    end.

%%--------------------------------------------------------------------
%% @doc
%% In case of a leaf sets the ID of its right sibling, otherwise does nothing.
%% @end
%%--------------------------------------------------------------------
-spec set_right_sibling(id(), bp_tree:tree_node()) -> bp_tree:tree_node().
set_right_sibling(NodeId, Node = #bp_tree_node{
    leaf = true, children = Children
}) ->
    {ok, Children2} = bp_tree_array:update({right, last}, NodeId, Children),
    Node#bp_tree_node{children = Children2};
set_right_sibling(_NodeId, Node = #bp_tree_node{leaf = false}) ->
    Node.

%%--------------------------------------------------------------------
%% @doc
%% Returns value associated with a key from leaf node or fails with a missing
%% error.
%% @end
%%--------------------------------------------------------------------
-spec find(bp_tree:key(), bp_tree:tree_node()) ->
    {ok, bp_tree:value()} | {error, not_found}.
find(Key, #bp_tree_node{leaf = true, children = Children}) ->
    case bp_tree_array:find(Key, Children) of
        {ok, Pos} -> bp_tree_array:get({left, Pos}, Children);
        {error, Reason} -> {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Returns position of a first key that does not compare less than a key.
%% @end
%%--------------------------------------------------------------------
-spec lower_bound(bp_tree:key(), bp_tree:tree_node()) -> pos_integer().
lower_bound(Key, #bp_tree_node{leaf = true, children = Children}) ->
    bp_tree_array:lower_bound(Key, Children).

%%--------------------------------------------------------------------
%% @doc
%% Inserts key-value pair into a node.
%% @end
%%--------------------------------------------------------------------
-spec insert(bp_tree:key(), bp_tree:value(), bp_tree:tree_node()) ->
    {ok, bp_tree:tree_node()} | {error, term()}.
insert(Key, Value, Node = #bp_tree_node{leaf = true, children = Children}) ->
    case bp_tree_array:insert({left, Key}, Value, Children) of
        {ok, Children2} -> {ok, Node#bp_tree_node{children = Children2}};
        {error, Reason} -> {error, Reason}
    end;
insert(Key, Value, Node = #bp_tree_node{leaf = false, children = Children}) ->
    case bp_tree_array:insert({both, Key}, Value, Children) of
        {ok, Children2} -> {ok, Node#bp_tree_node{children = Children2}};
        {error, Reason} -> {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Removes key and associated value from a node.
%% @end
%%--------------------------------------------------------------------
-spec remove(bp_tree:key(), bp_tree:tree_node()) ->
    {ok, bp_tree:tree_node()} | {error, term()}.
remove(Key, Node = #bp_tree_node{leaf = true, children = Children}) ->
    case bp_tree_array:remove({left, Key}, Children) of
        {ok, Children2} -> {ok, Node#bp_tree_node{children = Children2}};
        {error, Reason} -> {error, Reason}
    end;
remove(Key, Node = #bp_tree_node{leaf = false, children = Children}) ->
    case bp_tree_array:remove({right, Key}, Children) of
        {ok, Children2} -> {ok, Node#bp_tree_node{children = Children2}};
        {error, Reason} -> {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Merges two nodes into a single node.
%% @end
%%--------------------------------------------------------------------
-spec merge(bp_tree:tree_node(), bp_tree:key(), bp_tree:tree_node()) ->
    bp_tree:tree_node().
merge(Node = #bp_tree_node{leaf = true, children = LChildren}, _ParentKey,
    #bp_tree_node{leaf = true, children = RChildren}) ->
    LChildren2 = bp_tree_array:merge(LChildren, RChildren),
    Node#bp_tree_node{children = LChildren2};
merge(Node = #bp_tree_node{leaf = false, children = LChildren}, ParentKey,
    #bp_tree_node{leaf = false, children = RChildren}) ->
    {ok, LChildren2} = bp_tree_array:append({key, ParentKey}, ParentKey, LChildren),
    LChildren3 = bp_tree_array:merge(LChildren2, RChildren),
    Node#bp_tree_node{children = LChildren3}.

%%--------------------------------------------------------------------
%% @doc
%% Splits node in half. Returns updated original node, newly created one
%% and a key that should be inserted into parent node.
%% @end
%%--------------------------------------------------------------------
-spec split(bp_tree:tree_node()) ->
    {ok, bp_tree:tree_node(), bp_tree:key(), bp_tree:tree_node()}.
split(LNode = #bp_tree_node{leaf = true, children = Children}) ->
    {LChildren, Key, RChildren} = bp_tree_array:split(Children),
    {ok, LChildren2} = bp_tree_array:append({key, Key}, Key, LChildren),
    RNode = #bp_tree_node{leaf = true, children = RChildren},
    {ok, LNode#bp_tree_node{children = LChildren2}, Key, RNode};
split(LNode = #bp_tree_node{leaf = false, children = Children}) ->
    {LChildren, Key, RChildren} = bp_tree_array:split(Children),
    RNode = #bp_tree_node{leaf = false, children = RChildren},
    {ok, LNode#bp_tree_node{children = LChildren}, Key, RNode}.

%%--------------------------------------------------------------------
%% @doc
%% Moves maximum value from a left sibling to a node.
%% @end
%%--------------------------------------------------------------------
-spec rotate_right(bp_tree:tree_node(), bp_tree:key(), bp_tree:tree_node()) ->
    {bp_tree:tree_node(), bp_tree:key(), bp_tree:tree_node()}.
rotate_right(LNode = #bp_tree_node{leaf = true, children = LChildren},
    _ParentKey, RNode = #bp_tree_node{leaf = true, children = RChildren}) ->
    {ok, Key} = bp_tree_array:get({key, last}, LChildren),
    {ok, Value} = bp_tree_array:get({left, last}, LChildren),
    {ok, LChildren2} = bp_tree_array:remove({left, Key}, LChildren),
    {ok, RChildren2} = bp_tree_array:prepend({left, Key}, Value, RChildren),
    {ok, ParentKey2} = bp_tree_array:get({key, last}, LChildren2),
    {
        LNode#bp_tree_node{children = LChildren2},
        ParentKey2,
        RNode#bp_tree_node{children = RChildren2}
    };
rotate_right(LNode = #bp_tree_node{leaf = false, children = LChildren},
    ParentKey, RNode = #bp_tree_node{leaf = false, children = RChildren}) ->
    {ok, Key} = bp_tree_array:get({key, last}, LChildren),
    {ok, Value} = bp_tree_array:get({right, last}, LChildren),
    {ok, LChildren2} = bp_tree_array:remove({right, Key}, LChildren),
    {ok, RChildren2} = bp_tree_array:prepend({left, ParentKey}, Value, RChildren),
    {
        LNode#bp_tree_node{children = LChildren2},
        Key,
        RNode#bp_tree_node{children = RChildren2}
    }.

%%--------------------------------------------------------------------
%% @doc
%% Moves minimum value from a right sibling to a node.
%% @end
%%--------------------------------------------------------------------
-spec rotate_left(bp_tree:tree_node(), bp_tree:key(), bp_tree:tree_node()) ->
    {bp_tree:tree_node(), bp_tree:key(), bp_tree:tree_node()}.
rotate_left(LNode = #bp_tree_node{leaf = true, children = LChildren},
    _ParentKey, RNode = #bp_tree_node{leaf = true, children = RChildren}) ->
    {ok, Key} = bp_tree_array:get({key, first}, RChildren),
    {ok, Value} = bp_tree_array:get({left, first}, RChildren),
    {ok, RChildren2} = bp_tree_array:remove({left, Key}, RChildren),
    {ok, Next} = bp_tree_array:get({right, last}, LChildren),
    {ok, LChildren2} = bp_tree_array:append({both, Key}, {Value, Next}, LChildren),
    {
        LNode#bp_tree_node{children = LChildren2},
        Key,
        RNode#bp_tree_node{children = RChildren2}
    };
rotate_left(LNode = #bp_tree_node{leaf = false, children = LChildren},
    ParentKey, RNode = #bp_tree_node{leaf = false, children = RChildren}) ->
    {ok, Key} = bp_tree_array:get({key, first}, RChildren),
    {ok, Value} = bp_tree_array:get({left, first}, RChildren),
    {ok, RChildren2} = bp_tree_array:remove({left, Key}, RChildren),
    {ok, LChildren2} = bp_tree_array:append({right, ParentKey}, Value, LChildren),
    {
        LNode#bp_tree_node{children = LChildren2},
        Key,
        RNode#bp_tree_node{children = RChildren2}
    }.

%%--------------------------------------------------------------------
%% @doc
%% Replaces key with a new one in a node.
%% @end
%%--------------------------------------------------------------------
-spec replace_key(bp_tree:key(), bp_tree:key(), bp_tree:tree_node()) ->
    {ok, bp_tree:tree_node()} | {error, term()}.
replace_key(Key, NewKey, Node = #bp_tree_node{children = Children}) ->
    case bp_tree_array:find(Key, Children) of
        {ok, Pos} ->
            {ok, Children2} = bp_tree_array:update({key, Pos}, NewKey, Children),
            {ok, Node#bp_tree_node{children = Children2}};
        {error, Reason} ->
            {error, Reason}
    end.