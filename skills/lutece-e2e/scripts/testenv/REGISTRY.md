# Environnement de test — registry des conteneurs mock

Objectif : mocker **toutes les dépendances externes** dans des conteneurs locaux pour tester Lutèce
**de bout en bout**, sans jamais appeler un service réel. Activation à la carte (profils Docker).

```bash
bash testenv.sh up mail captcha   # ou : up all
bash testenv.sh down
```

## Mocks fournis

| Dépendance | Conteneur | Port(s) | Override Lutèce (pointer vers le mock) | Helper / vérif |
|---|---|---|---|---|
| **Mail** | MailHog | 1025 (SMTP), 8025 (API/UI) | `mail.server=localhost` · `mail.server.port=1025` | `tests/lib/mail.ts` (`waitForMail`) |
| **CAPTCHA** (CaptchEtat/PISTE) | WireMock | 8090 | `captchetat.api.token.url=http://localhost:8090/api/oauth/token` · `captchetat.api.url=http://localhost:8090/piste/captchetat/v2` | contact soumis → mail (MailHog) ; logs `/__admin/requests` |
| **SSO / OIDC** | *(à fournir)* Keycloak | 8081 | selon le module d'auth (`mylutece-openam.*`, `…/realms/<realm>/protocol/openid-connect/*`) | gabarit commenté dans `docker-compose.testenv.yml` + patron ci-dessous — **aucun realm n'est livré**, il est propre à chaque organisation |
| **Auth FO** | (pas un conteneur) utilisateur seedé | — | mylutece-database | `fo-login.spec.ts` |

## Ajouter un mock (patron)

Pour une nouvelle dépendance externe (ex. **CRM / guichet usager**, **IdentityStore**, **SSO**) :

1. **Conteneur** — ajouter un service dans `docker-compose.testenv.yml` avec un `profiles: ["<dep>", "all"]`.
   Squelette copiable (2e instance WireMock, port hôte **libre** — pris : 1025/8025/8090 ; 8081 réservé au gabarit OIDC) :
   ```yaml
     <dep>-mock:
       image: wiremock/wiremock:3.9.1
       container_name: lutece-e2e-<dep>
       profiles: ["<dep>", "all"]
       ports: ["8091:8080"]            # choisir un port hôte non listé ci-dessus
       volumes: ["./<dep>/mappings:/home/wiremock/mappings:ro"]
   ```
   Puis ajouter le profil à `testenv.sh` (bloc de vérif `up`) sur le modèle des existants.
2. **Câblage** — trouver la/les propriété(s) de conf Lutèce qui portent l'URL du service réel
   (souvent `<module>.*.url`), et les surcharger vers le mock (override + restart).
3. **Stubs** — pour WireMock, déposer des mappings JSON dans `<dep>/mappings/` (cf. `wiremock/mappings/`).
4. **Helper / assertion** — un helper (ou une requête) qui vérifie l'effet (message reçu, appel enregistré…).
5. **Registry** — ajouter une ligne au tableau ci-dessus.

### Repli « captcha désactivé en profil e2e »

Si le mock WireMock ne peut pas reproduire fidèlement le contrat PISTE captchetat v2 (limite connue), le
repli est de **désactiver la vérification captcha** dans la conf du site pour le profil de test : pointer les
`captchetat.api.*` vers WireMock **et** retirer/neutraliser l'appel captcha du template de contact (ou activer
un profil Maven `e2e` qui livre un `captcha` no-op). Ce n'est pas un contournement de CAPTCHA en production —
uniquement l'environnement de test local, jamais rec/prod.

**Principe (leçon CRM)** : le mock **répond toujours 200 et rapporte son verdict** (signature valide,
message reçu…) plutôt que de rejeter en 4xx — sinon il bloque le parcours et masque les autres vérifications.
**Le mock sert, le test juge.** Sans dépendance mockée, on ne teste que le chemin d'échec.
