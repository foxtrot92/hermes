# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  helper :all # include all helpers, all the time
  before_filter :set_return_to, :authenticate

  $OPERATORS = %w{ oneof regexp special }
  
  def authenticate

    if ICHAIN_MODE.to_s == 'on' || ICHAIN_MODE.to_s == 'simulate'
      login_via_ichain
    else
      basic_auth
    end
  end

  def basic_auth
    unless session[:user]
      # We use our own authentication
      if request.env.has_key? 'X-HTTP_AUTHORIZATION'
        # try to get it where mod_rewrite might have put it
        authorization = request.env['X-HTTP_AUTHORIZATION'].to_s.split
      elsif request.env.has_key? 'Authorization'
        # for Apace/mod_fastcgi with -pass-header Authorization
        authorization = request.env['Authorization'].to_s.split
      elsif request.env.has_key? 'HTTP_AUTHORIZATION'
        # this is the regular location
        authorization = request.env['HTTP_AUTHORIZATION'].to_s.split
      end
      logger.debug "authorization: #{authorization}"

      if ( authorization and authorization.size == 2 and
           authorization[0] == "Basic" )
        logger.debug( "AUTH2: #{authorization[1]}" )

        login, passwd = Base64.decode64( authorization[1] ).split(/:/)
        if login and passwd
          @loggedin_user = Person.authenticate login, pass
          if @loggedin_user 
            session[:user] = @loggedin_user
          end
        end
      end
    end

    unless session[:user]
      # if we still do not have a user in the session it's time to redirect.
      session[:return_to] = request.request_uri
      redirect_to :controller => 'account', :action => 'login'
      return
    end
  end



  def login_via_ichain

    # :ICHAIN_MODE is set in config/environments/development.rb
    if ICHAIN_MODE.to_s == 'simulate'
      user_name = "termite"
      http_email = "termite@suse.de"
      http_real_name = "Hans Peter Termitenhans"
      logger.debug("iChain debug mode, using static user #{user_name} (#{http_email})")
    else
      user_name  = request.env['HTTP_X_USERNAME']
      http_email = request.env['HTTP_X_EMAIL']
      http_first_name = request.env['HTTP_X_FIRSTNAME'] || ""
      http_last_name  = request.env['HTTP_X_LASTNAME'] || ""
      http_real_name = "#{http_first_name} #{http_last_name}"
      logger.debug("Extracted iChain data: #{user_name} (#{http_email})")
      logger.debug request.env.inspect
    end  
    
    # FIXME: Get information from api.opensuse.org/person/<user_name> and
    #        update/evaluate our database
    
    if !user_name.nil?
      @loggedin_user = Person.find_or_initialize_by_stringid( user_name )
      @loggedin_user.email = http_email
      @loggedin_user.name = http_real_name
      @loggedin_user.save
      session[:user] = @loggedin_user
    else
      session[:return_to] = request.request_uri
      redirect_to :controller => 'account', :action => 'login'
      return
    end
  end

  def redirect_to_index
    redirect_to :controller => :subscriptions
  end


  def current_user
    session[:user]
  end


  def logged_in?
    current_user.is_a? Person
  end
  
  
  def set_return_to
    session[:return_to] = request.request_uri
  end
  

  # See ActionController::RequestForgeryProtection for details
  # Uncomment the :secret if you're not using the cookie session store
  protect_from_forgery # :secret => '444c9e73283339dd0f004698ba1e3f85'
end
