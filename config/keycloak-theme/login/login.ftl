<#import "template.ftl" as layout>
<#-- REQUIRED: Keycloak does not auto-import `layout` for a custom theme; without this
     import FreeMarker throws "layout is null". -->
<@layout.registrationLayout displayMessage=!messagesPerField.existsError('username','password'); section>
    <#if section = "header">
        Company Name
    <#elseif section = "form">
        <div id="kc-form">
          <div id="kc-form-wrapper">
            <#if realm.password>
                <form id="kc-form-login" onsubmit="login.disabled = true; return true;" action="${url.loginAction}" method="post">
                    <#if !usernameHidden??>
                        <div class="${properties.kcFormGroupClass!}">
                            <label for="username" class="${properties.kcLabelClass!}">Username</label>
                            <input tabindex="1" id="username"
                                   class="${properties.kcInputClass!}" name="username"
                                   value="${(login.username!'')}" type="text" autofocus autocomplete="off"
                                   placeholder="Use UPN or Email"
                                   aria-invalid="<#if messagesPerField.existsError('username','password')>true</#if>" />
                            <div class="kc-field-hint">Sign in with your UPN or Email address</div>
                            <#if messagesPerField.existsError('username','password')>
                                <span id="input-error" class="${properties.kcInputErrorMessageClass!}" aria-live="polite">
                                    ${kcSanitize(messagesPerField.getFirstError('username','password'))?no_esc}
                                </span>
                            </#if>
                        </div>
                    </#if>

                    <div class="${properties.kcFormGroupClass!}">
                        <label for="password" class="${properties.kcLabelClass!}">Password</label>
                        <input tabindex="2" id="password"
                               class="${properties.kcInputClass!}" name="password"
                               type="password" autocomplete="off"
                               aria-invalid="<#if messagesPerField.existsError('username','password')>true</#if>" />
                    </div>

                    <div class="${properties.kcFormGroupClass!} ${properties.kcFormSettingClass!}">
                        <div id="kc-form-options">
                            <#if realm.rememberMe && !usernameHidden??>
                                <div class="checkbox">
                                    <label>
                                        <#if login.rememberMe??>
                                            <input tabindex="3" id="rememberMe" name="rememberMe" type="checkbox" checked> Remember me
                                        <#else>
                                            <input tabindex="3" id="rememberMe" name="rememberMe" type="checkbox"> Remember me
                                        </#if>
                                    </label>
                                </div>
                            </#if>
                        </div>
                    </div>

                    <div id="kc-form-buttons" class="${properties.kcFormGroupClass!}">
                        <input tabindex="4"
                               class="${properties.kcButtonClass!} ${properties.kcButtonPrimaryClass!} ${properties.kcButtonBlockClass!}"
                               name="login" id="kc-login" type="submit" value="Sign in"/>
                    </div>

                    <div id="kc-corp-footer">
                        <a href="https://www.example.com" target="_blank" rel="noopener">example.com</a>
                    </div>
                </form>
            </#if>
          </div>
        </div>
    </#if>
</@layout.registrationLayout>
