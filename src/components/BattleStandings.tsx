import { useMemo, useState } from 'react';
import { ordinal, rankPlayers, type BattlePlayer } from '../game/battle';

interface BattleStandingsProps {
  players: BattlePlayer[];
  selfId: string;
  /** The battle is decided; the panel offers the results instead of a rank. */
  finished: boolean;
  onShowResults: () => void;
}

/**
 * The live standings, riding the top-left corner of the board: this player's
 * position writ large, everyone's scores under it. Tapping the header folds
 * the list away to just the position, for small screens where the corner is
 * precious.
 */
export function BattleStandings({ players, selfId, finished, onShowResults }: BattleStandingsProps) {
  const [open, setOpen] = useState(true);

  const ranked = useMemo(() => rankPlayers(players.filter((p) => !p.waiting)), [players]);
  const self = ranked.find((entry) => entry.player.id === selfId);
  const selfOut = self !== undefined && (self.player.buried || !self.player.connected);

  return (
    <div className="battle-standings">
      <button
        type="button"
        className="battle-standings-head"
        aria-expanded={open}
        onClick={() => setOpen((was) => !was)}
      >
        <span className="battle-standings-rank">
          {self ? ordinal(self.rank) : '—'}
          <span className="battle-standings-of"> of {ranked.length}</span>
        </span>
        {selfOut && !finished && <span className="battle-standings-out">buried</span>}
        <span className="battle-standings-fold" aria-hidden="true">
          {open ? '▾' : '▸'}
        </span>
      </button>

      {open && (
        <ol className="battle-standings-list">
          {ranked.map(({ player, rank }) => (
            <li
              key={player.id}
              className={
                'battle-standings-row' +
                (player.id === selfId ? ' battle-standings-self' : '') +
                (player.buried || !player.connected ? ' battle-standings-buried' : '')
              }
            >
              <span className="battle-standings-place">{rank}</span>
              <span className="battle-standings-name">
                {player.name}
                {!player.connected && ' (left)'}
                {player.connected && player.buried && ' 💀'}
              </span>
              <span className="battle-standings-score">{player.score}</span>
            </li>
          ))}
        </ol>
      )}

      {open && finished && (
        <button type="button" className="btn btn-primary battle-standings-results" onClick={onShowResults}>
          Final standings
        </button>
      )}
    </div>
  );
}
