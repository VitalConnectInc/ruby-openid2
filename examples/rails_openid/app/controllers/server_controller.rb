require "pathname"

require "openid"
require "openid/consumer/discovery"
require "openid/extensions/sreg"
require "openid/extensions/pape"
require "openid/store/filesystem"

class ServerController < ApplicationController
  include ServerHelper
  include OpenID::Server
  layout nil

  def index
    begin
      oidreq = server.decode_request(params)
    rescue ProtocolError => e
      # invalid openid request, so just display a page with an error message
      render(text: e.to_s, status: 500)
      return
    end

    # no openid.mode was given
    unless oidreq
      render(text: "This is an OpenID server endpoint.")
      return
    end

    oidresp = nil

    if oidreq.is_a?(CheckIDRequest)

      identity = oidreq.identity

      if oidreq.id_select
        if oidreq.immediate
          oidresp = oidreq.answer(false)
        elsif session[:username].nil?
          # The user hasn't logged in.
          show_decision_page(oidreq)
          return
        else
          # Else, set the identity to the one the user is using.
          identity = url_for_user
        end
      end

      if oidresp
        nil
      elsif is_authorized(identity, oidreq.trust_root)
        oidresp = oidreq.answer(true, nil, identity)

        # add the sreg response if requested
        add_sreg(oidreq, oidresp)
        # ditto pape
        add_pape(oidreq, oidresp)

      elsif oidreq.immediate
        server_url = url_for(action: "index")
        oidresp = oidreq.answer(false, server_url)

      else
        show_decision_page(oidreq)
        return
      end

    else
      oidresp = server.handle_request(oidreq)
    end

    render_response(oidresp)
  end

  def show_decision_page(oidreq, message = "Do you trust this site with your identity?")
    session[:last_oidreq] = oidreq
    @oidreq = oidreq

    flash[:notice] = message if message

    render(template: "server/decide", layout: "server")
  end

  def user_page
    # Yadis content-negotiation: we want to return the xrds if asked for.
    accept = request.env["HTTP_ACCEPT"]

    # This is not technically correct, and should eventually be updated
    # to do real Accept header parsing and logic.  Though I expect it will work
    # 99% of the time.
    if accept and accept.include?("application/xrds+xml")
      user_xrds
      return
    end

    # content negotiation failed, so just render the user page
    xrds_url = url_for(controller: "user", action: params[:username]) + "/xrds"
    identity_page = <<~EOS
      <html><head>
      <meta http-equiv="X-XRDS-Location" content="#{xrds_url}" />
      <link rel="openid.server" href="#{url_for(action: "index")}" />
      </head><body><p>OpenID identity page for #{params[:username]}</p>
      </body></html>
    EOS

    # Also add the Yadis location header, so that they don't have
    # to parse the html unless absolutely necessary.
    response.headers["X-XRDS-Location"] = xrds_url
    render(text: identity_page)
  end

  def user_xrds
    types = [
      OpenID::OPENID_2_0_TYPE,
      OpenID::OPENID_1_0_TYPE,
      OpenID::SREG_URI,
    ]

    render_xrds(types)
  end

  def idp_xrds
    types = [
      OpenID::OPENID_IDP_2_0_TYPE,
    ]

    render_xrds(types)
  end

  def decision
    oidreq = session[:last_oidreq]
    session[:last_oidreq] = nil

    if params[:yes].nil?
      redirect_to(oidreq.cancel_url)
      nil
    else
      id_to_send = params[:id_to_send]

      identity = oidreq.identity
      if oidreq.id_select
        if id_to_send and id_to_send != ""
          session[:username] = id_to_send
          session[:approvals] = []
          identity = url_for_user
        else
          msg = "You must enter a username to in order to send " +
            "an identifier to the Relying Party."
          show_decision_page(oidreq, msg)
          return
        end
      end

      if session[:approvals]
        session[:approvals] << oidreq.trust_root
      else
        session[:approvals] = [oidreq.trust_root]
      end
      oidresp = oidreq.answer(true, nil, identity)
      add_sreg(oidreq, oidresp)
      add_pape(oidreq, oidresp)
      render_response(oidresp)
    end
  end

  protected

  def server
    if @server.nil?
      server_url = url_for(action: "index", only_path: false)
      dir = Pathname.new(RAILS_ROOT).join("db").join("openid-store")
      store = OpenID::Store::Filesystem.new(dir)
      @server = Server.new(store, server_url)
    end
    @server
  end

  def approved(trust_root)
    return false if session[:approvals].nil?

    session[:approvals].member?(trust_root)
  end

  def is_authorized(identity_url, trust_root)
    (session[:username] and (identity_url == url_for_user) and approved(trust_root))
  end

  def render_xrds(types)
    type_str = ""

    types.each do |uri|
      type_str += "<Type>#{uri}</Type>\n      "
    end

    yadis = <<~EOS
      <?xml version="1.0" encoding="UTF-8"?>
      <xrds:XRDS
          xmlns:xrds="xri://$xrds"
          xmlns="xri://$xrd*($v*2.0)">
        <XRD>
          <Service priority="0">
            #{type_str}
            <URI>#{url_for(controller: "server", only_path: false)}</URI>
          </Service>
        </XRD>
      </xrds:XRDS>
    EOS

    render(text: yadis, content_type: "application/xrds+xml")
  end

  def add_sreg(oidreq, oidresp)
    # check for Simple Registration arguments and respond
    sregreq = OpenID::SReg::Request.from_openid_request(oidreq)

    return if sregreq.nil?

    # In a real application, this data would be user-specific,
    # and the user should be asked for permission to release
    # it.
    sreg_data = {
      "nickname" => session[:username],
      "fullname" => "Mayor McCheese",
      "email" => "mayor@example.com",
    }

    sregresp = OpenID::SReg::Response.extract_response(sregreq, sreg_data)
    oidresp.add_extension(sregresp)
  end

  def add_pape(oidreq, oidresp)
    papereq = OpenID::PAPE::Request.from_openid_request(oidreq)
    return if papereq.nil?

    paperesp = OpenID::PAPE::Response.new
    paperesp.nist_auth_level = 0 # we don't even do auth at all!
    oidresp.add_extension(paperesp)
  end

  def render_response(oidresp)
    server.signatory.sign(oidresp) if oidresp.needs_signing
    web_response = server.encode_response(oidresp)

    case web_response.code
    when HTTP_OK
      render(text: web_response.body, status: 200)

    when HTTP_REDIRECT
      redirect_to(web_response.headers["location"])

    else
      render(text: web_response.body, status: 400)
    end
  end
end
