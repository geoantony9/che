<html>
<head>
${msg("robotoFontIncludeStyle")?no_esc}
</head>
<body style="${msg("mailBodyStyle")}">
    <#assign letterTitle=msg("identityProviderLinkTitle")>
    <#include "header.ftl">

    <div style="${msg("mailContentStyle")}">
        <p>${msg("identityProviderLinkLetterText", identityProviderAlias, realmName, identityProviderContext.username)}</p>
        ${msg("button", msg('identityProviderLinkButtonText'), link)?no_esc}
        <p>${msg("emailLinkExpirationText", linkExpiration)}</p>
    </div>

    <#include "footer.ftl">
</body>
</html>
