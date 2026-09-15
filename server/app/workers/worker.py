from ..config import settings


def main():
    from redis import Redis
    from rq import Worker, Queue

    conn = Redis.from_url(settings.redis_url)
    w = Worker([Queue("hue", connection=conn)], connection=conn)
    w.work()


if __name__ == "__main__":
    main()
