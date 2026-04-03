from gevent.pywsgi import WSGIServer
from server import app, init_redis
import os

redis_url = os.environ.get('REDIS_URL')
if redis_url:
    init_redis(redis_url)

port = int(os.environ.get('PORT', 8070))
http_server = WSGIServer(('0.0.0.0', port), app)
http_server.serve_forever()