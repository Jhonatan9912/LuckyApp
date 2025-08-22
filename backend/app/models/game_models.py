from app.db.database import db
from sqlalchemy import Column, Integer, SmallInteger, ForeignKey, DateTime, func, UniqueConstraint  # NUEVO
from sqlalchemy.orm import relationship

class Game(db.Model):
    __tablename__ = 'games'

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=True)  # opcional: quién abrió el juego
    played_at = Column(DateTime, server_default=func.now())

    # ---- CAMPOS QUE USAS EN EL SERVICIO ----
    state_id = Column(Integer, nullable=False, server_default='1')   # NUEVO: 1=en juego, 2=finalizado
    winning_number = Column(Integer, nullable=True)                  # NUEVO

    numbers = relationship("GameNumber", back_populates="game")

class GameNumber(db.Model):
    __tablename__ = 'game_numbers'

    id = Column(Integer, primary_key=True)
    game_id = Column(Integer, ForeignKey('games.id'), nullable=False)
    number = Column(Integer, nullable=False)            # 0..999
    position = Column(SmallInteger, nullable=False)     # 1..5
    taken_by = Column(Integer, ForeignKey('users.id'), nullable=False)
    taken_at = Column(DateTime, nullable=False, server_default=func.now())

    game = relationship("Game", back_populates="numbers")

    # Asegura que (game_id, number) sea único para que funcione ON CONFLICT (recomendado)
    __table_args__ = (
        UniqueConstraint('game_id', 'number', name='uq_game_number_per_game'),  # NUEVO (si aún no existe el índice único en DB)
    )
