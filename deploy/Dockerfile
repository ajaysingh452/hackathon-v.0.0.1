#Dockerfile
FROM nginx:alpine

RUN rm -rf /usr/share/nginx/html/*

COPY web/ /usr/share/nginx/html/
COPY deploy/nginx.conf /etc/nginx/nginx.conf

RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html