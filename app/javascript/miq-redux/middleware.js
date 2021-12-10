import thunk from 'redux-thunk';
import { routerMiddleware } from 'connected-react-router';
import promiseMiddleware from 'redux-promise-middleware';

export const taggingMiddleware = store => next => action => {
  const { type, meta, tagCategory, tag } = action;
  if (meta && meta.url) {
    const params = {id: store.getState().tagging.appState.affectedItems[0], cat: tag.tagCategory.id, val: tag.tagValue.id, check: 1, tree_typ: 'tags' };
    if (type === 'UI-COMPONENTS_TAGGING_TOGGLE_TAG_VALUE_CHANGE') {
      $.post(meta.url, params)
    } else if (type === 'UI-COMPONENTS_TAGGING_DELETE_ASSIGNED_TAG') {
      $.post(meta.url, {...params, check: 0})
    }
  }
  let result = next(action)
  return result;
}

export default history => [
  routerMiddleware(history),
  taggingMiddleware,
  thunk,
  promiseMiddleware(),
];
