# Lightweight base image: Alpine Linux + Nginx.
FROM nginx:1.27-alpine

LABEL maintainer="akifhameed" \
      description="Akif Hameed digital CV served by Nginx" \
      version="1.0"

# Remove the default Nginx placeholder page.
RUN rm -rf /usr/share/nginx/html/*

# Copy the static portfolio files into Nginx's web root.
COPY index.html /usr/share/nginx/html/
COPY styles.css /usr/share/nginx/html/

# Nginx listens on port 80 inside the container by default.
# The application will be accessed on host port 8081 using:
# docker run -d --name portfolio-cv -p 8081:80 akifhameed/cv:1.0
EXPOSE 80

# Start Nginx in the foreground so the container keeps running.
CMD ["nginx", "-g", "daemon off;"]
