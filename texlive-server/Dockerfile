FROM ubuntu:24.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -q -y \
        python3 \
        python3-venv \
        python3-dev \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv "$VIRTUAL_ENV"
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

COPY requirements.txt /app/requirements.txt
RUN pip install --upgrade pip setuptools wheel \
 && pip install "Cython<3" \
 && pip install --no-binary gevent --no-build-isolation -r /app/requirements.txt

COPY . /app
WORKDIR /app
CMD ["python3", "wsgi.py"]
