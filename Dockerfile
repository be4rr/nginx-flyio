# Use an official Python runtime as a parent image
FROM python:3.9-slim as base

RUN apt update -y && apt install nginx -y

# Set the working directory
WORKDIR /app

# Copy the Flask app
COPY . /app

# Install Flask
RUN pip install -r requirements.txt

COPY nginx.conf /etc/nginx/nginx.conf

RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]



