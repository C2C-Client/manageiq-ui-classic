import React from 'react';
import { shallow, mount } from 'enzyme';
import { shallowToJson } from 'enzyme-to-json';
import SecretSwitchField from '../../components/async-credentials/secret-switch-field';
import { FieldProviderComponent as FieldProvider } from '../helpers/fieldProvider';

const DummyComponent = ({
  isDisabled,
  validateOnMount, // eslint-disable-line
  validate, // eslint-disable-line
  editMode, // eslint-disable-line
  buttonLabel,
  setEditMode,
  ...props
}) => <button {...props} onClick={setEditMode} disabled={isDisabled} type="button">{buttonLabel || 'Dummy'}</button>;

describe('Secret switch field component', () => {
  let initialProps;
  let changeSpy;
  let getStateSpy;
  beforeEach(() => {
    changeSpy = jest.fn();
    getStateSpy = jest.fn().mockReturnValue({
      values: {},
    });
    initialProps = {
      FieldProvider,
      edit: false,
      formOptions: {
        renderForm: ([secret]) => <DummyComponent {...secret} />,
        change: changeSpy,
        getState: getStateSpy,
      },
    };
  });

  afterEach(() => {
    changeSpy.mockReset();
  });

  it('should render correctly in non edit mode', () => {
    const wrapper = mount(<SecretSwitchField {...initialProps} />);
    expect(shallowToJson(wrapper)).toMatchSnapshot();
  });

  it('should render correctly in edit mode', () => {
    const wrapper = mount(<SecretSwitchField {...initialProps} edit />);
    expect(shallowToJson(wrapper)).toMatchSnapshot();
  });

  /**
   * Hooks are not supported in enzyme jest.
   * Instead of adding another testing utilities we can wait for while until its added or until we know enzyme will not support hooks
   * and we can use another library
   * https://github.com/airbnb/enzyme/issues/2011
   */
  it('should render correctly switch to editing', () => {
    const wrapper = mount(<SecretSwitchField {...initialProps} edit />);
    wrapper.find('button').simulate('click');
    expect(changeSpy).toHaveBeenCalled();
  });
});
