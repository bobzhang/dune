open Import

let (>>=) = Future.(>>=)
let (>>|) = Future.(>>|)

module type Elt = sig
  type t
  type graph
  type key
  val key : t -> key
  val deps : t -> graph -> t list
end

module Make(Key : Set.OrderedType)(Elt : Elt with type key := Key.t) = struct
  module Set = Set.Make(Key)

  let top_closure graph elements =
    let visited = ref Set.empty in
    let res = ref [] in
    let rec loop elt ~temporarily_marked =
      let key = Elt.key elt in
      if Set.mem key temporarily_marked then
        Error [elt]
      else if not (Set.mem key !visited) then begin
        visited := Set.add key !visited;
        let temporarily_marked = Set.add key temporarily_marked in
        match iter_elts (Elt.deps elt graph) ~temporarily_marked with
        | Ok () -> res := elt :: !res; Ok ()
        | Error l -> Error (elt :: l)
      end else
        Ok ()
    and iter_elts elts ~temporarily_marked =
      match elts with
      | [] -> Ok ()
      | elt :: elts ->
        match loop elt ~temporarily_marked with
        | Error _ as result -> result
        | Ok () -> iter_elts elts ~temporarily_marked
    in
    match iter_elts elements ~temporarily_marked:Set.empty with
    | Ok () -> Ok (List.rev !res)
    | Error elts -> Error elts
end

module type Elt_fut = sig
  type t
  type graph
  type key
  val key : t -> key
  val deps : t -> graph -> t list Future.t
end

module Make_fut(Key : Set.OrderedType)(Elt : Elt_fut with type key := Key.t) = struct
  module Set = Set.Make(Key)

  let top_closure graph elements =
    let visited = ref Set.empty in
    let res = ref [] in
    let rec loop elt ~temporarily_marked =
      let key = Elt.key elt in
      if Set.mem key temporarily_marked then
        Future.return (Error [elt])
      else if not (Set.mem key !visited) then begin
        visited := Set.add key !visited;
        let temporarily_marked = Set.add key temporarily_marked in
        Elt.deps elt graph
        >>= fun deps ->
        iter_elts deps ~temporarily_marked
        >>| function
        | Ok () -> res := elt :: !res; Ok ()
        | Error l -> Error (elt :: l)
      end else
        Future.return (Ok ())
    and iter_elts elts ~temporarily_marked =
      match elts with
      | [] -> Future.return (Ok ())
      | elt :: elts ->
        loop elt ~temporarily_marked
        >>= function
        | Error _ as result -> Future.return result
        | Ok () -> iter_elts elts ~temporarily_marked
    in
    iter_elts elements ~temporarily_marked:Set.empty
    >>| function
    | Ok () -> Ok (List.rev !res)
    | Error elts -> Error elts
end
