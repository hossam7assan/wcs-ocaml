open Lwt
open Wcs_t

let version = "version=2017-02-03"

(** {6. Check workspaces} *)

let ws_check ws =
  let check_node_names nodes =
    let tbl = Hashtbl.create 7 in
    List.iter
      (fun node ->
        if Hashtbl.mem tbl node.node_dialog_node then
          raise (Failure ("Multiple nodes with name "^node.node_dialog_node));
        Hashtbl.add tbl node.node_dialog_node true)
      nodes
  in
  check_node_names ws.ws_dialog_nodes;
  true


(** {6. Utility functions} *)

let parameters_of_json (o: json) : string =
  begin match o with
  | `Assoc [] -> ""
  (* | `Assoc ((x, v) :: l) -> *)
  (*     let params = "?"^x^"="^(Yojson.Basic.to_string o) in *)
  (*     List.fold_left *)
  (*       (fun params (x, v) -> *)
  (*         "&"^x^"="^(Yojson.Basic.to_string o)) *)
  (*       params l *)
  | `Assoc l ->
      List.fold_left
        (fun params (x, v) ->
          begin match v with
          | `String s -> "&"^x^"="^s
          | _ -> "&"^x^"="^(Yojson.Basic.to_string o)
          end)
        "" l
  | _ ->
      Log.error "Wcs" (Some "")
        ("parameters_of_json "^ (Yojson.Basic.pretty_to_string o) ^
         ": json object expected")
  end

(** {6. Generic functions} *)

let post wcs_cred method_ req =
  let uri =
    Uri.of_string (wcs_cred.cred_url^method_^"?"^version)
  in
  let headers =
    let h = Cohttp.Header.init () in
    let h = Cohttp.Header.add_authorization h (`Basic (wcs_cred.cred_username, wcs_cred.cred_password)) in
    let h = Cohttp.Header.add h "Content-Type" "application/json" in
    h
  in
  let data = ((Cohttp.Body.of_string req) :> Cohttp_lwt_body.t) in
  let call =
    Cohttp_lwt_unix.Client.post ~body:data ~headers uri >>= fun (resp, body) ->
      let code = resp |> Cohttp.Response.status |> Cohttp.Code.code_of_status in
      body |> Cohttp_lwt_body.to_string >|= fun body ->
        begin match code with
        | 200 | 201 -> body
        | _ ->
            Log.error
              "Wcs" None
              (Format.sprintf "[POST %s] %d: %s" method_ code body)
        end
  in
  let rsp = Lwt_main.run call in
  rsp

let get wcs_cred method_ params =
  let uri =
    Uri.of_string (wcs_cred.cred_url^method_^"?"^version^params)
  in
  let headers =
    let h = Cohttp.Header.init () in
    let h = Cohttp.Header.add_authorization h (`Basic (wcs_cred.cred_username, wcs_cred.cred_password)) in
    let h = Cohttp.Header.add h "Content-Type" "application/json" in
    h
  in
  let call =
    Cohttp_lwt_unix.Client.get ~headers uri >>= fun (resp, body) ->
      let code = resp |> Cohttp.Response.status |> Cohttp.Code.code_of_status in
      body |> Cohttp_lwt_body.to_string >|= fun body ->
        begin match code with
        | 200 -> body
        | _ ->
            Log.error
              "Wcs" None
              (Format.sprintf "[GET %s] %d: %s" method_ code body)
        end
  in
  let rsp = Lwt_main.run call in
  rsp


let delete wcs_cred method_ =
  let uri =
    Uri.of_string (wcs_cred.cred_url^method_^"?"^version)
  in
  let headers =
    let h = Cohttp.Header.init () in
    let h = Cohttp.Header.add_authorization h (`Basic (wcs_cred.cred_username, wcs_cred.cred_password)) in
    let h = Cohttp.Header.add h "Content-Type" "application/json" in
    h
  in
  let call =
    Cohttp_lwt_unix.Client.delete ~headers uri >>= fun (resp, body) ->
      let code = resp |> Cohttp.Response.status |> Cohttp.Code.code_of_status in
      body |> Cohttp_lwt_body.to_string >|= fun body ->
        begin match code with
        | 200 | 201 -> body
        | _ ->
            Log.error
              "Wcs" None
              (Format.sprintf "[DELETE %s] %d: %s" method_ code body)
        end
  in
  let rsp = Lwt_main.run call in
  rsp


(** {Watson Conversation API} *)

let list_workspaces wcs_cred req =
  let method_ = "/v1/workspaces" in
  let params =
    parameters_of_json (Json_util.json_of_list_workspaces_request req)
  in
  let rsp = get wcs_cred method_ params in
  Wcs_j.list_workspaces_response_of_string rsp


let create_workspace wcs_cred workspace =
  assert (ws_check workspace);
  let method_ = "/v1/workspaces" in
  let req = Wcs_j.string_of_workspace workspace in
  let rsp =
    begin try post wcs_cred method_ req
    with Log.Error ("Wcs", err) ->
      begin match workspace.ws_name with
      | Some ws_name ->
          Log.error
            "Wcs" None
            (Format.sprintf "[%s]%s" ws_name err)
      | None ->
          Log.error "Wcs" None err
      end
    end
  in
  Wcs_j.create_response_of_string rsp

let delete_workspace wcs_cred workspace_id =
  let method_ = "/v1/workspaces/"^workspace_id in
  let rsp = delete wcs_cred method_ in
  ignore rsp

let get_workspace wcs_cred req =
  let method_ = "/v1/workspaces/"^req.get_ws_req_workspace_id in
  let params =
    begin match req.get_ws_req_export with
    | None -> ""
    | Some b -> "&export="^(string_of_bool b)
    end
  in
  let rsp = get wcs_cred method_ params in
  Wcs_j.workspace_of_string rsp


(* XXXXXXXXXXXXXXXXXXXXXXXXX *)

let message wcs_cred workspace_id req_msg =
  let method_ = "/v1/workspaces/"^workspace_id^"/message" in
  let req = Wcs_j.string_of_message_request req_msg in
  let rsp = post wcs_cred method_ req in
  Wcs_j.message_response_of_string rsp

let update_workspace wcs_cred workspace_id workspace =
  assert (ws_check workspace);
  let method_ = "/v1/workspaces/"^workspace_id in
  let req = Wcs_j.string_of_workspace workspace in
  let rsp =
    begin try post wcs_cred method_ req
    with Log.Error ("Wcs", err) ->
      begin match workspace.ws_name with
      | Some ws_name ->
          Log.error
            "Wcs" None
            (Format.sprintf "[%s]%s" ws_name err)
      | None ->
          Log.error "Wcs" None err
      end
    end
  in
  ignore rsp
