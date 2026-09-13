from ..config import settings
from . import runner
from redis import Redis
from rq import Worker, Queue


def main():
    conn = Redis.from_url(settings.redis_url)
    w = Worker([Queue("hue", connection=conn)], connection=conn)
    w.work()


if __name__ == "__main__":
    main()
