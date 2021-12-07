import React from 'react';
import { shallow, mount } from 'enzyme';
import { shallowToJson } from 'enzyme-to-json';
import { HelpBlock } from 'patternfly-react';
import EditSecretField from '../../components/async-credentials/edit-secret-field';
import { FieldProviderComponent as FieldProvider } from '../helpers/fieldProvider';

describe('Edit secret field form component', () => {
  let initialProps;
  beforeEach(() => {
    initialProps = {
      label: 'foo',
      setEditMode: jest.fn(),
      FieldProvider,
    };
  });

  it('should render correctly', () => {
    const wrapper = shallow(<EditSecretField {...initialProps} />);
    expect(shallowToJson(wrapper)).toMatchSnapshot();
  });

  it('should render correctly in error state', () => {
    const wrapper = mount(
      <EditSecretField
        {...initialProps}
        FieldProvider={props => <FieldProvider {...props} meta={{ error: 'Error message' }} />}
      />,
    );
    expect(wrapper.find(HelpBlock)).toBeTruthy();
  });

  it('should call setEditMode on input button click', () => {
    const setEditMode = jest.fn();
    const wrapper = mount(<EditSecretField {...initialProps} setEditMode={setEditMode} />);
    wrapper.find('button').simulate('click');
    expect(setEditMode).toHaveBeenCalled();
  });
});
