from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "appdb"
    db_user: str = "appadmin"
    db_password: str = ""


settings = Settings()
