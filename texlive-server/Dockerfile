FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -q -y \
    python3 \
    python3-pip
COPY . /app
RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install "Cython<3" && \
    python3 -m pip install --no-binary gevent --no-build-isolation -r /app/requirements.txt
WORKDIR /app
CMD ["python3", "wsgi.py"]