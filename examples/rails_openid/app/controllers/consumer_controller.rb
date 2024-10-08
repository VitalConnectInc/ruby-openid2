require "pathname"

require "openid"
require "openid/extensions/sreg"
require "openid/extensions/pape"
require "openid/store/filesystem"

class ConsumerController < ApplicationController
  layout nil

  def index
    # render an openid form
  end

  def start
    begin
      identifier = params[:openid_identifier]
      if identifier.nil?
        flash[:error] = "Enter an OpenID identifier"
        redirect_to(action: "index")
        return
      end
      oidreq = consumer.begin(identifier)
    rescue OpenID::OpenIDError => e
      flash[:error] = "Discovery failed for #{identifier}: #{e}"
      redirect_to(action: "index")
      return
    end
    if params[:use_sreg]
      sregreq = OpenID::SReg::Request.new
      # required fields
      sregreq.request_fields(%w[email nickname], true)
      # optional fields
      sregreq.request_fields(%w[dob fullname], false)
      oidreq.add_extension(sregreq)
      oidreq.return_to_args["did_sreg"] = "y"
    end
    if params[:use_pape]
      papereq = OpenID::PAPE::Request.new
      papereq.add_policy_uri(OpenID::PAPE::AUTH_PHISHING_RESISTANT)
      papereq.max_auth_age = 2 * 60 * 60
      oidreq.add_extension(papereq)
      oidreq.return_to_args["did_pape"] = "y"
    end
    oidreq.return_to_args["force_post"] = "x" * 2048 if params[:force_post]
    return_to = url_for(action: "complete", only_path: false)
    realm = url_for(action: "index", id: nil, only_path: false)

    if oidreq.send_redirect?(realm, return_to, params[:immediate])
      redirect_to(oidreq.redirect_url(realm, return_to, params[:immediate]))
    else
      render(text: oidreq.html_markup(realm, return_to, params[:immediate], {"id" => "openid_form"}))
    end
  end

  def complete
    # FIXME: - url_for some action is not necessarily the current URL.
    current_url = url_for(action: "complete", only_path: false)
    parameters = params.reject { |k, _v| request.path_parameters[k] }
    parameters.reject! { |k, _v| %w[action controller].include?(k.to_s) }
    oidresp = consumer.complete(parameters, current_url)
    case oidresp.status
    when OpenID::Consumer::FAILURE
      flash[:error] = if oidresp.display_identifier
        "Verification of #{oidresp.display_identifier} " \
          "failed: #{oidresp.message}"
      else
        "Verification failed: #{oidresp.message}"
      end
    when OpenID::Consumer::SUCCESS
      flash[:success] = "Verification of #{oidresp.display_identifier}  " \
        "succeeded."
      if params[:did_sreg]
        sreg_resp = OpenID::SReg::Response.from_success_response(oidresp)
        sreg_message = "Simple Registration data was requested"
        if sreg_resp.empty?
          sreg_message << ", but none was returned."
        else
          sreg_message << ". The following data were sent:"
          sreg_resp.data.each do |k, v|
            sreg_message << "<br/><b>#{k}</b>: #{v}"
          end
        end
        flash[:sreg_results] = sreg_message
      end
      if params[:did_pape]
        pape_resp = OpenID::PAPE::Response.from_success_response(oidresp)
        pape_message = "A phishing resistant authentication method was requested"
        pape_message << if pape_resp.auth_policies.member?(OpenID::PAPE::AUTH_PHISHING_RESISTANT)
          ", and the server reported one."
        else
          ", but the server did not report one."
        end
        pape_message << "<br><b>Authentication time:</b> #{pape_resp.auth_time} seconds" if pape_resp.auth_time
        pape_message << "<br><b>NIST Auth Level:</b> #{pape_resp.nist_auth_level}" if pape_resp.nist_auth_level
        flash[:pape_results] = pape_message
      end
    when OpenID::Consumer::SETUP_NEEDED
      flash[:alert] = "Immediate request failed - Setup Needed"
    when OpenID::Consumer::CANCEL
      flash[:alert] = "OpenID transaction cancelled."
    end
    redirect_to(action: "index")
  end

  private

  def consumer
    if @consumer.nil?
      dir = Pathname.new(RAILS_ROOT).join("db").join("cstore")
      store = OpenID::Store::Filesystem.new(dir)
      @consumer = OpenID::Consumer.new(session, store)
    end
    @consumer
  end
end
