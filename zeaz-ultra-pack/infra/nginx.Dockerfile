FROM nginx:alpine
COPY infra/nginx.conf /etc/nginx/nginx.conf
COPY infra/certs /etc/nginx/certs
COPY infra/panels/admin /usr/share/nginx/html/admin
COPY infra/panels/user /usr/share/nginx/html/user
COPY infra/panels/devops /usr/share/nginx/html/devops
